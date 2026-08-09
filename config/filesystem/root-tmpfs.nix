{
  foundrixModules,
  traitTypes,
  lib,
  ...
}:
{
  imports = [
    foundrixModules.framework.traits.filesystem
  ];

  config = {
    # Announce volatile root trait
    foundrix.traits.filesystem.rootType = traitTypes.filesystem.rootType.volatile;

    # A mutable /etc overlay puts its upper layer on this tmpfs root, so
    # everything userborn persists there — the uid allocation above all —
    # is re-dealt on every boot. That only looks stable while the system
    # user set never changes: adding or removing a user can shift the uids
    # of existing users out from under their on-disk state. Immutable
    # moves userborn's files to /var/lib/nixos, where they persist beside
    # the state they describe. The other runtime /etc residents already
    # have volatile-root handling of their own (machine-id and sshd host
    # keys persist to /var/etc via config/filesystem/var.nix).
    system.etc.overlay.mutable = lib.mkDefault false;

    fileSystems."/" = {
      fsType = "tmpfs";
      options = [
        "size=10%"
        "noatime"
        "mode=0755"
        "uid=0"
        "gid=0"
      ];
    };
  };
}
