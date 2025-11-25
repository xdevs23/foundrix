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
  environment.etc = {
    "machine-id".source = "/var/etc/machine-id";

    "ssh/ssh_host_rsa_key".source = "/var/etc/ssh/ssh_host_rsa_key";
    "ssh/ssh_host_rsa_key.pub".source = "/var/etc/ssh/ssh_host_rsa_key.pub";
    "ssh/ssh_host_ed25519_key".source = "/var/etc/ssh/ssh_host_ed25519_key";
    "ssh/ssh_host_ed25519_key.pub".source = "/var/etc/ssh/ssh_host_ed25519_key.pub";
  };
  systemd.tmpfiles.settings = {
    "persistent-etc" = {
      "/var/etc" = {
        d = {
          mode = "0755";
          user = "0";
          group = "0";
        };
      };
      "/var/etc/ssh" = {
        d = {
          mode = "0755";
          user = "0";
          group = "0";
        };
      };
    };
  };
}
