{
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
}
