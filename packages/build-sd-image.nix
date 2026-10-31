{
  writeShellApplication,
  jq,
  rockflasher,
  systemd,
  util-linux,
  fakeroot,
  dosfstools,
  mtools,
  e2fsprogs,
  squashfs-tools,
  erofs-utils,
  btrfs-progs,
  xfsprogs,
}:
writeShellApplication {
  name = "build-sd-image";
  runtimeInputs = [
    jq
    rockflasher
    systemd
    util-linux
    fakeroot
    dosfstools
    mtools
    e2fsprogs.bin
    squashfs-tools
    erofs-utils
    btrfs-progs
    xfsprogs
  ];
  text = ''
    if [ $# -ne 2 ]; then
      echo "Usage: build-sd-image DESCRIPTION DESTINATION" >&2
      echo "Pass the sdImageDescription file exported by a system, then a block device or an image file path to write." >&2
      exit 1
    fi
    description=$1
    destination=$2

    if ! jq --exit-status 'has("rockflasherFlags") and has("repartFlags") and has("environment")' "$description" > /dev/null; then
      echo "$description does not contain all of rockflasherFlags, repartFlags and environment. Pass the sdImageDescription file exported by a system built with the same foundrix revision as this build-sd-image." >&2
      exit 1
    fi

    if [ -d "$destination" ]; then
      echo "$destination is a directory. Pass a block device or the path to an image file." >&2
      exit 1
    fi
    if [ -e "$destination" ]; then
      writeTarget=$destination
    else
      writeTarget=$(dirname -- "$destination")
    fi
    if [ ! -w "$writeTarget" ]; then
      echo "Cannot write to $writeTarget. Check that it exists, and run build-sd-image as a user that can write to it, for example with sudo for a block device." >&2
      exit 1
    fi

    workdir=$(mktemp --directory)
    trap 'rm -rf "$workdir"' EXIT

    jq --raw-output0 '.rockflasherFlags[]' "$description" > "$workdir/rockflasher-flags"
    jq --raw-output0 '.repartFlags[]' "$description" > "$workdir/repart-flags"
    jq --raw-output0 '.environment | to_entries[] | "\(.key)=\(.value)"' "$description" > "$workdir/environment"
    mapfile -d "" -t rockflasherFlags < "$workdir/rockflasher-flags"
    mapfile -d "" -t repartFlags < "$workdir/repart-flags"
    mapfile -d "" -t environment < "$workdir/environment"
    env "''${environment[@]}" unshare --map-root-user fakeroot systemd-repart --offline=yes \
      "''${repartFlags[@]}" "$workdir/disk.raw" > "$workdir/repart-output.json"

    rockflasher \
      "''${rockflasherFlags[@]}" \
      --repart "$workdir/repart-output.json" \
      --no-fill \
      --destination "$destination"
  '';
}
