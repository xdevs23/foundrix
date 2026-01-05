# Filesystem mount configuration.
# The image modules set sensible defaults for device paths and mount options.
# You only need to configure deployment-specific settings here.
{
  foundrixModules,
  ...
}:
{
  imports = [
    foundrixModules.config.filesystem.root-tmpfs   # Ephemeral root on tmpfs
    foundrixModules.config.filesystem.esp          # EFI System Partition
    foundrixModules.config.filesystem.nix          # /nix mount (auto-configured by image module)
    foundrixModules.config.filesystem.var          # /var mount (auto-configured by runtime module)
    foundrixModules.config.filesystem.home-tmpfs   # Ephemeral /home on tmpfs
  ];

  # Persist identity across reboots
  foundrix.config.filesystem.var.persistMachineId = true;
  foundrix.config.filesystem.var.persistSshHostKeys = true;

  # Home directory size (tmpfs)
  foundrix.config.filesystem.home-tmpfs.size = "1G";
}
