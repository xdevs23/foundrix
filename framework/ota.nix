{
  lib,
  config,
  pkgs,
  namespaced,
  namespacedCfg,
  ...
}:
{
  options = namespaced __curPos {
    updateServer = lib.mkOption {
      type = lib.types.str;
      description = "Update server URL for OTA updates";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
    in
    {
      systemd.sysupdate = {
        enable = true;

        transfers = {
          "10-uki-remote" = {
            Source = {
              MatchPattern = [
                "${config.boot.uki.name}_@v.efi.xz"
                "${config.boot.uki.name}_@v.efi.gz"
                "${config.boot.uki.name}_@v.efi"
              ];

              Path = cfg.updateServer;
              Type = "url-file";
            };

            Target = {
              MatchPattern = [
                "${config.boot.uki.name}_@v.efi"
              ];

              Path = "/EFI/Linux";
              PathRelativeTo = "boot";

              Type = "regular-file";
            };

            Transfer = {
              ProtectVersion = "%A";
            };
          };

          "20-store-remote" = {
            Source = {
              MatchPattern = [
                "store_@v.img.xz"
                "store_@v.img.gz"
                "store_@v.img"
              ];

              Path = cfg.updateServer;
              Type = "url-file";
            };

            Target = {
              Path = "auto";
              MatchPattern = "store_@v";
              Type = "partition";
            };

            Transfer = {
              ProtectVersion = "%A";
            };
          };
        };
      };

      environment.systemPackages = [
        (pkgs.runCommand "systemd-sysupdate" { } ''
          mkdir -p $out/bin
          ln -s ${config.systemd.package}/lib/systemd/systemd-sysupdate $out/bin
        '')
      ];
    };
}
