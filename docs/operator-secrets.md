# Operator-provided secrets: `services/operator-secrets.nix`

Some secrets cannot be generated on the host: they originate elsewhere and
must be carried in by a human. The Forgejo OIDC client credentials are the
motivating case — Zitadel on core-infra mints them, dev-infra consumes them,
and nothing may transport them automatically.

`services/secrets.nix` covers the other half of the problem (secrets the
host generates for itself) and is untouched by this design. The two are
complementary: `secrets` *generates*, `operator-secrets` *collects*.

Threat model: the secret must not sit in the nix store (world-readable) or
in git. It may rest on `/var`, which is why consumers of this mechanism are
expected to run `/var` on LUKS (`config/filesystem/var-luks.nix`).

## Shape

A ratatui prompt, modelled on `packages/var-disk-manager`, that blocks the
boot until every configured secret is present **and proven valid**. One
process collects *all* outstanding secrets in a single operator session,
rather than one prompt per consumer.

- **`packages/operator-secrets`** — a Rust daemon (`operator-secretsd`)
  plus a ratatui client (`operator-secrets-tui`), same split and for the
  same reason as var-disk-manager: the daemon owns the state machine and
  serves it over a unix socket (`/run/operator-secrets/sock`), so the
  console UI and any SSH session render the same screen and any of them
  can answer. A headless Hetzner box must be fillable over SSH; console-only
  would mean driving the provider's web console.
- **`services/operator-secrets.nix`** — declares the secrets, wires the
  daemon before its consumers, and is the single source of truth for
  identity (names, fields, output paths, validation commands), passed to
  the daemon as CLI flags.

## Declaring a secret

```nix
foundrix.services.operator-secrets.secrets.forgejo-oidc = {
  description = "Forgejo OIDC client credentials (from core-infra Zitadel)";
  fields = {
    CLIENT_ID = { order = 10; };
    CLIENT_SECRET = { order = 20; sensitive = true; };
  };
  validateCommand = [
    (lib.getExe (pkgs.callPackage (foundrix + "/packages/oidc-credential-validator") { }))
    "--issuer"
    "https://sso.example.com"
  ];
  path = "/var/credentials/forgejo-oidc.env";
  owner = "forgejo";
  mode = "0400";
  requiredBy = [ "forgejo.service" ];
};
```

Output is env-file format (`KEY=VALUE`, one per line, mode from `mode`) —
the format `systemd`'s `EnvironmentFile=` already reads, so consumers need
no adapter. `fields` may hold more than one value; the `sensitive` flag
only controls whether the TUI echoes it and whether the value may be
pre-filled into a re-prompt.

An attrset has no order of its own, so the order the operator is asked in
— and the order of the lines in the output file — comes from each field's
`order` (default 1000, ties broken by name). Leave it alone for
alphabetical; set it when an identifier should precede its secret.

`validateCommand` is an **argv list**, never a shell string: program path
followed by flags. No shell is involved in spawning it, so a value can
never be word-split or interpreted.

The validator is reached with `pkgs.callPackage` on its path rather than
through `foundrixPkgs`: `foundrixPkgs` is built by
`lib.filesystem.packagesFromDirectoryRecursive`, which keys on
`package.nix`, and foundrix's directory-based packages (this one,
`operator-secrets`, `var-disk-manager`) use `default.nix`. They are
therefore not exposed as `foundrixPkgs.<name>` — the name resolves to a
scope and `lib.getExe` fails eval. `config/filesystem/var-luks.nix`
reaches `var-disk-manager` the same way.

## Validation contract

`validateCommand` may be `null` for secrets that have no external proof
(e.g. ZeroSSL EAB credentials, where a real check would be a full ACME
account exchange): acceptance is then "every declared field present and
non-empty", for the stored file and prompted input alike. Prefer a real
validator whenever one exists — presence-only acceptance catches missing
fields, not wrong values.

Otherwise `validateCommand` is an ordinary executable (a compiled binary or a Deno
script — **never a shell script**; the values must not pass through a shell).
The daemon speaks to it over **stdio in JSON**, so no secret ever touches
argv (world-readable in `/proc`) or the environment (inherited by children,
visible in `/proc/<pid>/environ`):

- **stdin** — one JSON object: `{ "fields": { "CLIENT_ID": "…",
  "CLIENT_SECRET": "…" } }`. The daemon writes it, closes stdin.
- **stdout** — one JSON object: `{ "status": "valid" | "invalid" | "error",
  "message": "…" }`. `message` is optional and shown in the TUI.

The `status` field is authoritative — not the exit code — and maps straight
onto the state machine:

| `status`  | Meaning                                   | Daemon action              |
| --------- | ----------------------------------------- | -------------------------- |
| `valid`   | credential proven good                    | accept / release           |
| `invalid` | credential is wrong                       | reject, re-prompt          |
| `error`   | validator could not decide (e.g. SSO down)| block and report, no write |

A validator that crashes, exits non-zero without emitting JSON, or prints
unparseable output is treated as `error` — never as `invalid`. This is the
distinction that stops a transient network failure from rewriting a good
secret. Validation runs before anything is written to disk.

This is what makes "properly configured" provable rather than hoped-for.
For Forgejo the validator discovers
`https://<ssoDomain>/.well-known/openid-configuration` and probes the
**RFC 7662 introspection endpoint** with a throwaway token: authenticating
the introspection call is itself the proof of `CLIENT_ID`/`CLIENT_SECRET`,
needs no grant on the client, and — decisively — works for app clients on
Zitadel, which reserves the `client_credentials` grant for service
accounts (a correct app credential gets `invalid_client` from its token
endpoint, indistinguishable from a wrong secret). Providers without an
introspection endpoint fall back to a `client_credentials` token request.
A typo, a stale secret, or a wrong-instance credential is caught at entry
(`invalid`) instead of surfacing as a broken login hours later; an
unreachable SSO host is `error`, and the boot waits rather than discarding
a working secret.

Validation also runs against the **already-stored** file on every boot.
That is deliberate: it turns the regenerated-secret failure mode into a
self-healing prompt instead of a silently broken login. A secret that
still validates costs one request and never prompts; boots stay unattended
in the steady state.

### Known exception: the consumer's own handling

The mechanism guarantees the value never reaches argv, the environment,
the journal or the store *while it is in our hands*. What a consumer does
with the env-file afterwards is outside that boundary, and one consumer
currently weakens it:

Forgejo's `forgejo admin auth add-oauth|update-oauth` takes the client
secret **only** as `--secret <value>` (verified against forgejo-lts 15.0.3
`--help`: there is no file, stdin or documented env alternative). So for
the duration of that command, in `forgejo.service`'s `preStart`, the
secret is visible in the world-readable `/proc/<pid>/cmdline` to any local
unprivileged user. The window is short and the exposure is local-only, but
it is real and it is not something this module can fix — it would need a
change in Forgejo. Recorded here so it is a known, bounded exception
rather than an assumed-airtight chain.

## State machine

| Stored file | Validates | Action                                      |
| ----------- | --------- | ------------------------------------------- |
| absent      | —         | prompt, validate, write, release             |
| present     | yes       | release immediately (steady state)           |
| present     | no        | prompt (pre-filled with non-sensitive parts) |
| present     | validator unreachable | block, report — never silently pass |

A validator that cannot reach its dependency (SSO down, no network yet) is
**not** treated as invalid: rewriting a good secret because the network was
late would be worse than waiting. It blocks and says so.

## Editing a stored secret

The daemon only ever asks for what is missing, and its socket goes away with
the boot that collected on it. To rotate a password or move a service to a
different host afterwards:

```
operator-secrets-tui --edit              # pick from what this host declares
operator-secrets-tui --edit backup-smb   # go straight to one
```

That starts `operator-secrets-edit.service` — the same daemon with `--edit`,
on a socket of its own so it can never take the boot collector's — and
attaches to it. The answer goes through the same validation, ownership and
atomic write as one entered at first boot, and the stored file is untouched
until a new answer has been accepted. One secret per session; the session
exits when the edit does, and expires by itself if it is abandoned.

Root only, like everything else here: anyone who can reach the socket decides
which credential the host trusts.

Two deliberate asymmetries with the boot flow:

- The secrets listed in the picker are classified but **not** validated. An
  unreachable validator parks a boot on purpose; hanging an interactive
  command on a third party being reachable — for secrets the operator has not
  even asked to touch — has nothing to park for. The one that is chosen is
  validated normally, on the answer that is entered.
- Nothing is restarted afterwards. A consumer that must react to a changed
  credential watches its own file (`services/backup/smb.nix` is the worked
  example, with a `.path` unit that re-applies the destination). Reusing
  `requiredBy` as a restart list would overload it: it means "must not start
  before this exists", not "restart when this changes".

## Boot ordering

The daemon is `Before=multi-user.target` **and
`Wants=`+`Before=getty-pre.target`** — ordering against a target delays
only the target unit itself, not its member services, which systemd starts
in parallel; `Before=getty.target` therefore holds back *nothing* (proven
the hard way, twice). `getty-pre.target` is upstream's hook for exactly
this: every getty template ships `After=getty-pre.target`, so one passive
target gates every login prompt, including generator-created serial
consoles. Ordering only, deliberately no `Requires=` — a getty has no data
dependency on the collector, and `Requires` would propagate a collector
restart into killing console login sessions. Consumers additionally `Requires=`/`After=` the daemon via
`requiredBy`. It is ordered **after** `sshd.service`, the network, and
`nss-user-lookup.target` (it resolves secret owners up front), for two
reasons: the operator must be able to SSH in to answer, and the validator
needs the network to reach the SSO host. So: sshd and networking come up,
then the boot parks at the prompt, then consumers and gettys start. If the
collector itself fails, `OnFailure=emergency.target` stops the boot from
sailing into a half-up multi-user with credential-less services.

Consequence: `forgejo.service` no longer needs its
`ConditionPathExists` guard on the credentials file — the dependency
expresses the requirement properly, and a missing credential now blocks
with an explanation instead of a silently-not-started unit.

## dev-infra integration

Two changes beyond adopting the module:

1. **`/var` moves to LUKS.** The secret rests on `/var`; on the current
   repart-provisioned volume that is cleartext on a Hetzner disk. Switch
   `runtime.repart.var` → `filesystem.var-luks` with
   `volumeGlob = "/dev/disk/by-id/scsi-0HC_Volume_*"` (the glob the device
   config already uses). **No dev-infra host is deployed yet**, so both are
   simply *born* encrypted (`blank only` in the var-luks state machine) and
   the migration flow in [var-luks.md](var-luks.md) does not apply here.
2. **The initrd SSH port must be overridden.** `config/initrd/ssh.nix`
   defaults to **2222**, and dev-infra's admin sshd also listens on 2222
   (Forgejo owns 22). Same host:port with two different host keys is
   exactly the host-key-changed collision that dedicated port exists to
   avoid. dev-infra sets the initrd port to 2223.

Note the resulting operator experience: every boot blocks twice on first
setup — once in the initrd for the LUKS passphrase, once in the main system
for any outstanding secret — and thereafter only for LUKS. Unattended
reboots are already an outage under var-luks; this adds no new class of
interruption.

## Rejected alternatives

- **Copy the file out-of-band by hand** (the status quo). No integrity
  check, silently stale after any secret rotation, and the failure surfaces
  as a broken login rather than at the point of change.
- **Push credentials core-infra → dev-infra automatically.** Requires
  core-infra to hold deploy credentials for dev-infra and a trusted channel
  between environments, widening blast radius for a value that changes
  approximately never. Rejected in favour of a human carrying it.
- **Prompt in the initrd, like var-disk-manager.** `/var` is not mounted
  there, so the secret could not be persisted where it belongs, and the
  validator would need the initrd's network stack to reach SSO. The
  credential is not needed until a main-system service starts; blocking
  that late is both sufficient and much less plumbing.
- **Never persist; prompt every boot.** Strongest at-rest posture, but it
  makes every reboot an outage for a value that is stable by design. LUKS
  on `/var` gets the at-rest property without the recurring toil.
- **A separate prompt per consuming service.** Multiple competing
  fullscreen UIs on one console, and an operator who cannot see what else
  is outstanding. One session collects everything.
- **Validation by regex/length in Nix.** A well-formed wrong secret passes,
  which is the failure this mechanism exists to prevent. Calling a binary
  keeps the check as strong as the consumer needs and keeps protocol
  knowledge out of the module.
