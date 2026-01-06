{
  foundrixModules,
  traitTypes,
  ...
}:
{
  imports = [
    foundrixModules.framework.traits.filesystem
  ];

  config = {
    # Announce volatile root trait
    foundrix.traits.filesystem.rootType = traitTypes.filesystem.rootType.volatile;

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
