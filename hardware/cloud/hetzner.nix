{
  pkgs,
  modulesPath,
  foundrixModules,
  ...
}:
{
  imports = [
    "${modulesPath}/profiles/qemu-guest.nix"
    foundrixModules.config.image.boot.systemd-boot-bios
  ];

  services.cloud-init.enable = false;

  # Online disk resize: detect capacity changes and grow filesystem
  services.udev.extraRules = ''
    ACTION=="change", SUBSYSTEM=="block", ENV{RESIZE}=="1", ENV{DEVTYPE}=="disk", TAG+="systemd", ENV{SYSTEMD_WANTS}="disk-online-resize@%k.service"
  '';

  systemd.services."disk-online-resize@" = {
    description = "Online resize for /dev/%i";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "disk-online-resize" ''
        disk="/dev/$1"

        echo "Disk $disk resized, running repart..."
        ${pkgs.systemd}/bin/systemd-repart --dry-run=no "$disk"

        part=$(${pkgs.util-linux}/bin/lsblk -ln -o NAME "$disk" | tail -1)
        mountpoint=$(${pkgs.util-linux}/bin/findmnt -n -o TARGET "/dev/$part" 2>/dev/null)

        if [ -z "$mountpoint" ]; then
          echo "No mountpoint found for /dev/$part, skipping resize" >&2
          exit 0
        fi

        unit="systemd-growfs@$(systemd-escape --path "$mountpoint").service"
        echo "Growing filesystem at $mountpoint"
        systemctl restart "$unit"
      ''} %i";
    };
  };
}
