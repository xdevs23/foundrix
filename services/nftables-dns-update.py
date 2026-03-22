"""Resolve hostnames and atomically update nftables sets for egress filtering.

Uses the libnftables Python bindings (JSON API) for all nftables operations
and socket.getaddrinfo for DNS resolution. No subprocess calls needed.
"""

import hashlib
import json
import socket
import sys
import time

import nftables


def resolve_host(host: str) -> tuple[set[str], set[str]]:
    """Resolve a hostname to sets of IPv4 and IPv6 addresses."""
    ipv4s: set[str] = set()
    ipv6s: set[str] = set()
    try:
        for family, _, _, _, sockaddr in socket.getaddrinfo(host, None):
            if family == socket.AF_INET:
                ipv4s.add(sockaddr[0])
            elif family == socket.AF_INET6:
                ipv6s.add(sockaddr[0])
    except socket.gaierror as e:
        print(f"  WARNING: DNS resolution failed for {host}: {e}", file=sys.stderr)
    return ipv4s, ipv6s


def collect_elements(
    connections: list[dict],
) -> dict[str, set[tuple[str, int]]]:
    """Resolve all connections and collect (ip, port) pairs per protocol+family."""
    elements: dict[str, set[tuple[str, int]]] = {
        "tcp_v4": set(),
        "tcp_v6": set(),
        "udp_v4": set(),
        "udp_v6": set(),
    }

    for conn in connections:
        host = conn["host"]
        ports = conn["ports"]
        proto = conn["protocol"]
        print(f"Resolving {host} ({proto})...")

        ipv4s, ipv6s = resolve_host(host)
        for ip in ipv4s:
            for port in ports:
                print(f"  IPv4: {ip} . {port}")
                elements[f"{proto}_v4"].add((ip, port))
        for ip in ipv6s:
            for port in ports:
                print(f"  IPv6: {ip} . {port}")
                elements[f"{proto}_v6"].add((ip, port))

        if not ipv4s and not ipv6s:
            print(f"  WARNING: No addresses found for {host}", file=sys.stderr)

    return elements


def elements_hash(elements: dict[str, set[tuple[str, int]]]) -> str:
    """Short hash of all elements for set naming."""
    data = json.dumps(
        {k: sorted(v) for k, v in sorted(elements.items()) if v},
        sort_keys=True,
    )
    return hashlib.sha256(data.encode()).hexdigest()[:8]


def find_drop_handle_and_old_sets(
    nft: nftables.Nftables, table: str, chain: str, proto: str
) -> tuple[int | None, list[int], list[str]]:
    """List chain rules, find drop handle, old dynamic rule handles and set names."""
    rc, output, error = nft.json_cmd(
        {"nftables": [{"list": {"chain": {"family": "inet", "table": table, "name": chain}}}]}
    )
    if rc != 0:
        print(f"ERROR listing chain: {error}", file=sys.stderr)
        return None, [], []

    drop_handle = None
    old_handles: list[int] = []
    old_sets: list[str] = []
    prefix = f"allowed_dynamic_{proto}_"

    for item in output.get("nftables", []):
        rule = item.get("rule")
        if not rule:
            continue
        rule_json = json.dumps(rule)

        if '"drop"' in rule_json and '"oifname"' in rule_json:
            drop_handle = rule.get("handle")

        if prefix in rule_json:
            old_handles.append(rule["handle"])
            for word in rule_json.split('"'):
                if word.startswith(prefix):
                    old_sets.append(word)

    return drop_handle, old_handles, old_sets


def nft_update(nft: nftables.Nftables, elements: dict, config: dict) -> None:
    """Atomically replace dynamic rules: delete old, create new in one batch."""
    table = config["table"]
    chain = config["chain"]
    iface = config["interfaceMatch"]
    h = elements_hash(elements)

    nft.set_handle_output(True)

    for proto in ("tcp", "udp"):
        v4_elems = elements[f"{proto}_v4"]
        v6_elems = elements[f"{proto}_v6"]

        if not v4_elems and not v6_elems:
            print(f"No {proto} elements, skipping")
            continue

        new_v4 = f"allowed_dynamic_{proto}_ipv4_{h}"
        new_v6 = f"allowed_dynamic_{proto}_ipv6_{h}"

        drop_handle, old_handles, old_sets = find_drop_handle_and_old_sets(
            nft, table, chain, proto
        )

        # Build a single atomic batch: delete old rules/sets, create new sets,
        # add elements, insert rules — all applied as one transaction.
        stmts: list[str] = []

        for handle in old_handles:
            stmts.append(f"delete rule inet {table} {chain} handle {handle}")
        for set_name in set(old_sets):
            stmts.append(f"delete set inet {table} {set_name}")

        stmts.append(
            f"add set inet {table} {new_v4} "
            f"{{ type ipv4_addr . inet_service ; flags interval ; }}"
        )
        stmts.append(
            f"add set inet {table} {new_v6} "
            f"{{ type ipv6_addr . inet_service ; flags interval ; }}"
        )

        if v4_elems:
            elem_str = ", ".join(f"{ip} . {port}" for ip, port in v4_elems)
            stmts.append(f"add element inet {table} {new_v4} {{ {elem_str} }}")
        if v6_elems:
            elem_str = ", ".join(f"{ip} . {port}" for ip, port in v6_elems)
            stmts.append(f"add element inet {table} {new_v6} {{ {elem_str} }}")

        if drop_handle is not None:
            if v4_elems:
                stmts.append(
                    f"insert rule inet {table} {chain} position {drop_handle} "
                    f"oifname {iface} ip daddr . {proto} dport @{new_v4} accept"
                )
            if v6_elems:
                stmts.append(
                    f"insert rule inet {table} {chain} position {drop_handle} "
                    f"oifname {iface} ip6 daddr . {proto} dport @{new_v6} accept"
                )

        batch = "\n".join(stmts)
        rc, _, error = nft.cmd(batch)
        if rc != 0:
            print(f"ERROR in atomic {proto} update: {error}", file=sys.stderr)
            continue

        print(f"{proto}: {len(v4_elems)} v4, {len(v6_elems)} v6 elements")


def main() -> None:
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <config.json>", file=sys.stderr)
        sys.exit(1)

    with open(sys.argv[1]) as f:
        config = json.load(f)

    connections = config["connections"]
    if not connections:
        print("No dynamic hosts configured, skipping")
        return

    # Retry with exponential backoff (network may not be ready at boot)
    elements = None
    for attempt in range(1, 6):
        elements = collect_elements(connections)
        if any(elements.values()):
            break
        if attempt == 5:
            print("WARNING: DNS resolution failed after 5 attempts", file=sys.stderr)
            return
        delay = 2 ** (attempt - 1)
        print(f"DNS resolution failed, retrying in {delay}s (attempt {attempt}/5)...")
        time.sleep(delay)

    nft_obj = nftables.Nftables()
    nft_update(nft_obj, elements, config)
    print("DNS update complete")


if __name__ == "__main__":
    main()
