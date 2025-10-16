{ pkgs, lib, ... }:
{
  "x86_64" =
    {
      systemDisk,
      additionalDisks ? [ ],
      serialShellPath ? null,
      journalShellPath ? null,
      hostForwards ? [ ],
      ...
    }:
    pkgs.writeShellScriptBin "launch-qemu-x86_64-${builtins.baseNameOf systemDisk}" ''
      ${lib.getExe' pkgs.qemu_kvm "qemu-system-x86_64"} \
        -M q35,nvdimm=on \
        -M accel=kvm:tcg \
        -cpu host \
        -m 8G,slots=2,maxmem=16G \
        -smp sockets=1,dies=1,cores=4,threads=1 \
        -bios ${pkgs.OVMF.fd}/FV/OVMF.fd \
        -device qemu-xhci,id=xhci \
        -drive "format=raw,file=${systemDisk}" \
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
        -device virtio-gpu-pci,edid=on,yres=720,xres=1280 \
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
    '';
}
