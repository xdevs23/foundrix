{
  fileSystems."/home" = {
    fsType = "tmpfs";
    options = [
      "size=10%"
      "noatime"
    ];
    neededForBoot = true;
  };
}
