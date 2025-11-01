{
  security.virtualisation.flushL1DataCache = "always";
  security.forcePageTableIsolation = true;
  boot.kernel.sysctl = {
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
  };
}
