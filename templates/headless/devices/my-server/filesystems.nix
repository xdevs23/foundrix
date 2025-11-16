{ foundrixModules, ... }:
{
  imports = [
    # Remove this if your root is non-volatile
    foundrixModules.config.filesystem.root-tmpfs
    # The default configuration is usually sufficient,
    # but you can always configure it yourself
    foundrixModules.config.filesystem.esp
  ];

  fileSystems = {
    # Add your mounts here
  };

  boot.initrd.luks = {
    # Configure LUKS here
  };
}
