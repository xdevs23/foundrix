{
  foundrixModules,
  traitTypes,
  config,
  lib,
  ...
}:
let
  # ConfigurationDirectory may be a string or a list of strings
  configDirsOf =
    service:
    let
      value = service.serviceConfig.ConfigurationDirectory or "";
    in
    if builtins.isList value then value else lib.optional (value != "") value;
  configDirUnits = lib.filterAttrs (_: service: configDirsOf service != [ ]) config.systemd.services;
in
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

    # systemd creates ConfigurationDirectory= paths under /etc at service
    # start, which fails before exec on a read-only /etc (exit status
    # 241/CONFIGURATION_DIRECTORY). Catch such units at evaluation time;
    # the fix is to reset the directive and materialize the directory via
    # environment.etc (see config/networking/network-discovery.nix).
    assertions = lib.optional (!config.system.etc.overlay.mutable) {
      assertion = configDirUnits == { };
      message = ''
        These units set ConfigurationDirectory=, which systemd cannot create on an
        immutable /etc overlay: ${lib.concatStringsSep ", " (builtins.attrNames configDirUnits)}
        Reset the directive and provide the directory via environment.etc instead.
      '';
    };

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
