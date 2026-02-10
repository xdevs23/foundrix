{ pkgs, lib, ... }:
{
  closureInfo,
  uki,
  additionalDisks ? [ ],
  persistentDisks ? [ ],
  serialShellPath ? null,
  journalShellPath ? null,
  hostForwards ? [ ],
  ...
}:
let
  espDir = pkgs.runCommandLocal "esp-dir" { } ''
    mkdir -p $out/EFI/BOOT
    cp --reflink=auto ${uki} $out/EFI/BOOT/BOOT${pkgs.stdenv.hostPlatform.efiArch}.efi
  '';
in
pkgs.writeShellScriptBin "launch-qemu-closure-${pkgs.stdenv.hostPlatform.qemuArch}" ''
  set -euo pipefail

  DATA_DIR="''${XDG_DATA_HOME:-$HOME/.local/share}/foundrix/vms"
  storePath="$DATA_DIR/nix-store"
  espPath="$DATA_DIR/esp"

  if command -v qemu-system-${pkgs.stdenv.hostPlatform.qemuArch} &>/dev/null; then
    qemu_command=qemu-system-${pkgs.stdenv.hostPlatform.qemuArch}
    qemu_img=qemu-img
  else
    qemu_command="${lib.getExe' pkgs.qemu_kvm "qemu-system-${pkgs.stdenv.hostPlatform.qemuArch}"}"
    qemu_img="${lib.getExe' pkgs.qemu_kvm "qemu-img"}"
  fi

  mkdir -p "$storePath"

  rm -rf "''${espPath:?}"
  cp -r ${espDir} "$espPath"
  chmod -R +w "$espPath"

  ${lib.concatMapStringsSep "\n  " (
    disk:
    ''[ -f "$DATA_DIR/${disk.name}.qcow2" ] || "$qemu_img" create -f qcow2 "$DATA_DIR/${disk.name}.qcow2" ${disk.size}''
  ) persistentDisks}

  if [ -f "$storePath/.closure-ref" ] && [ "$(cat "$storePath/.closure-ref")" = "${closureInfo}" ]; then
    echo "Nix store up to date ($(wc -l < ${closureInfo}/store-paths) paths)"
  else
    requiredPaths=$(sed 's|/nix/store/||' ${closureInfo}/store-paths | sort)
    currentPaths=$(find "$storePath" -maxdepth 1 -mindepth 1 -not -name '.*' -printf '%f\n' 2>/dev/null | sort)

    toDelete=$(comm -23 <(echo "$currentPaths") <(echo "$requiredPaths"))
    toAdd=$(comm -13 <(echo "$currentPaths") <(echo "$requiredPaths"))

    deleteCount=$(echo "$toDelete" | grep -c . || true)
    addCount=$(echo "$toAdd" | grep -c . || true)
    echo "Syncing nix store: +$addCount -$deleteCount ($(wc -l < ${closureInfo}/store-paths) total)"

    resolvedDataDir=$(realpath "''${DATA_DIR:?}")
    for path in $toDelete; do
      [ -n "$path" ] || continue
      target=$(realpath -m "''${storePath:?}/$path")
      [[ "$target" == "$resolvedDataDir"/* ]] || continue
      chmod -R u+w "$target" 2>/dev/null || true
      rm -rf "$target"
    done

    for path in $toAdd; do
      [ -n "$path" ] || continue
      cp --reflink=auto -a "/nix/store/$path" "$storePath/"
    done

    echo "${closureInfo}" > "$storePath/.closure-ref"
  fi

  exec "$qemu_command" \
    ${lib.optionalString pkgs.stdenv.hostPlatform.isx86_64 ''
      -M q35,nvdimm=on \
      -M accel=kvm:tcg \
      -device virtio-gpu-pci,edid=on,yres=720,xres=1280 \
      -bios ${pkgs.OVMF.fd}/FV/OVMF.fd \
      ${lib.optionalString (
        pkgs.stdenv.buildPlatform.system == pkgs.stdenv.hostPlatform.system
        && pkgs.stdenv.buildPlatform.isx86_64
      ) ''-cpu host \''}
    ''} \
    ${lib.optionalString pkgs.stdenv.hostPlatform.isAarch64 ''
      -machine virt-9.2 \
      -accel tcg \
      -cpu cortex-a57 \
      -drive if=pflash,format=raw,file=${pkgs.qemu}/share/qemu/edk2-aarch64-code.fd,readonly=on \
      -device virtio-gpu-pci \
    ''} \
    -m 8G,slots=2,maxmem=16G \
    -smp sockets=1,dies=1,cores=4,threads=1 \
    -device qemu-xhci,id=xhci \
    -device usb-tablet,bus=xhci.0 \
    -drive file=fat:rw:"$espPath",format=raw \
    -virtfs local,path="$storePath",mount_tag=store,security_model=none,readonly=on \
    ${
      lib.concatMapStringsSep " \\\n    " (
        disk: ''-drive format=qcow2,file="$DATA_DIR/${disk.name}.qcow2"''
      ) persistentDisks
    } \
    ${lib.concatMapStringsSep " " (disk: "-drive ${lib.escapeShellArg disk}") additionalDisks} \
    -chardev stdio,id=stdio0 \
    -serial chardev:stdio0 \
    ${
      if serialShellPath == null then
        ""
      else
        ''
          -chardev socket,id=serialshell,path=${serialShellPath},server=on,wait=off \
          -serial chardev:serialshell \
        ''
    } \
    ${
      if journalShellPath == null then
        ""
      else
        ''
          -chardev socket,id=journalshell,path=${journalShellPath},server=on,wait=off \
          -serial chardev:journalshell \
        ''
    } \
    -parallel none \
    -display gtk,gl=on,show-cursor=off \
    -vga none \
    ${
      lib.concatStringsSep "," (
        [
          "-nic user,model=virtio-net-pci"
        ]
        ++ (lib.map (fwd: "hostfwd=${fwd}") hostForwards)
      )
    } \
    -boot c
''
