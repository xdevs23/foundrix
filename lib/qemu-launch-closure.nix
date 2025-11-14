{ pkgs, lib, ... }:
{
  closure,
  uki,
  additionalDisks ? [ ],
  serialShellPath ? null,
  journalShellPath ? null,
  hostForwards ? [ ],
  ...
}:
pkgs.writeShellScriptBin "launch-qemu-closure-${pkgs.stdenv.hostPlatform.qemuArch}" ''
  qemu_command="qemu-system-${pkgs.stdenv.hostPlatform.qemuArch}"
  if ! command -V $qemu_command 2>/dev/null >/dev/null; then
    qemu_command="${lib.getExe' pkgs.qemu_kvm "qemu-system-${pkgs.stdenv.hostPlatform.qemuArch}"}"
  fi
  $qemu_command \
    ${lib.optionalString pkgs.stdenv.hostPlatform.isx86_64 ''
      -M q35,nvdimm=on \
      -M accel=kvm:tcg \
      -device virtio-gpu-pci,edid=on,yres=720,xres=1280 \
      -bios ${pkgs.OVMF.fd}/FV/OVMF.fd \
      ${lib.optionalString (
        pkgs.stdenv.buildPlatform.system == pkgs.stdenv.hostPlatform.system &&
        pkgs.stdenv.buildPlatform.isx86_64
      ) ''-cpu host \''}
    ''} \
    ${lib.optionalString pkgs.stdenv.hostPlatform.isAarch64 ''
      -machine virt-9.2 \
      -accel tcg \
      -cpu cortex-a57 \
      -drive if=pflash,format=raw,file=${
        pkgs.qemu
      }/share/qemu/edk2-aarch64-code.fd,readonly=on \
      -device virtio-gpu-pci \
    ''} \
    -m 8G,slots=2,maxmem=16G \
    -smp sockets=1,dies=1,cores=4,threads=1 \
    -device qemu-xhci,id=xhci \
    -device usb-tablet,bus=xhci.0 \
    -drive file=fat:ro:${
      pkgs.runCommandLocal "" { } ''
        mkdir -p $out/EFI/BOOT
        cp --reflink=auto ${uki} $out/EFI/BOOT/BOOT${
          pkgs.stdenv.hostPlatform.efiArch
        }.efi
      ''
    },format=raw \
    -virtfs local,path=${closure},mount_tag=store,security_model=none \
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
    -boot c \
    -snapshot
''
