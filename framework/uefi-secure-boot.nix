{
  namespaced,
  lib,
  pkgs,
  namespacedCfg,
  ...
}:
let
  msUUID = "77fa9abd-0359-4d32-bd60-28f4e78f784b";
  msKeys =
    let
      cfg = (namespacedCfg __curPos).keys;
    in
    rec {
      dbWin2011 = pkgs.fetchurl {
        name = "Microsoft Windows Production PCA 2011.crt";
        url = "https://go.microsoft.com/fwlink/p/?linkid=321192";
        hash = "sha256-6OlfBzOlXoute+ChQT7iPFH86mSzyPpqeGk1/dzHGWE=";
      };
      dbUefi2011 = pkgs.fetchurl {
        name = "Microsoft Corporation UEFI CA 2011.crt";
        url = "https://go.microsoft.com/fwlink/p/?linkid=321194";
        hash = "sha256-SOmbmR9X/FL3YUlZm/8KWMRxVCKbn41gOsQNNQAkhQc=";
      };
      kek2011 = pkgs.fetchurl {
        name = "Microsoft Corporation KEK CA 2011.crt";
        url = "https://go.microsoft.com/fwlink/p/?linkid=321185";
        hash = "sha256-oRF/UWoyzvy6Py0azhCoeXL9a76P4NC5luCeZdgCpQM=";
      };
      dbWin2023 = pkgs.fetchurl {
        name = "Windows UEFI CA 2023.crt";
        url = "https://go.microsoft.com/fwlink/p/?linkid=2239776";
        hash = "sha256-B28f6pCsKRVev3fBdoL3Xx/dG+GW2jAtyEYeNQqa4zA=";
      };
      dbUefi2023 = pkgs.fetchurl {
        name = "Microsoft UEFI CA 2023.crt";
        url = "https://go.microsoft.com/fwlink/p/?linkid=2239872";
        hash = "sha256-9hJONBJb7j/m15pXTqp7kcDnvZ2SnBoyEXjv1hHa2QE=";
      };
      dbOptionRom2023 = pkgs.fetchurl {
        name = "Microsoft Option ROM UEFI CA 2023.crt";
        url = "https://go.microsoft.com/fwlink/p/?linkid=2284009";
        hash = "sha256-5b4+ZMbmaigUV+zezg1tB4dXeq0qOgFEJiwQwUuo2PE=";
      };
      kek2023 = pkgs.fetchurl {
        name = "Microsoft Corporation KEK 2K CA 2023.crt";
        url = "https://go.microsoft.com/fwlink/p/?linkid=2239775";
        hash = "sha256-PNPwMJ7a4ih2epdt1A2fSv/E+9Uhjy6Mw8ndl+isb50=";
      };
      dbInstallList =
        (lib.optional cfg.includeLegacyWindows dbWin2011)
        ++ (lib.optional cfg.includeLegacyMSUEFI dbUefi2011)
        ++ (lib.optional cfg.includeWindows dbWin2023)
        ++ (lib.optional cfg.includeMSUEFI dbUefi2023)
        ++ (lib.optional cfg.includeMSOptionROM dbOptionRom2023);
      kekInstallList =
        (lib.optional (cfg.includeLegacyWindows || cfg.includeLegacyMSUEFI) kek2011)
        ++ (lib.optional (cfg.includeWindows || cfg.includeMSUEFI || cfg.includeMSOptionROM) kek2023);
    };
in
{
  options = namespaced __curPos {
    keys = {
      includeWindows = lib.mkEnableOption "Windows 2023 secure boot keys";
      includeMSUEFI = lib.mkEnableOption "MS UEFI 2023 secure boot keys";
      includeMSOptionROM = lib.mkEnableOption "MS Option ROM 2023 secure boot keys";
      includeLegacyWindows = lib.mkEnableOption "Windows 2011 secure boot keys";
      includeLegacyMSUEFI = lib.mkEnableOption "MS UEFI 2011 secure boot keys";
    };
  };

  config = {
    system.build.secureBoot.keys = {
      msDbEsl =
        let
          sbsiglist = lib.getExe' pkgs.sbsigntool "sbsiglist";
        in
        pkgs.runCommandLocal "secureboot-ms-db-esl" { } ''
          mkdir -p $out
          ${lib.concatStringsSep "\n" (
            builtins.map (file: ''
              ${sbsiglist} \
                --owner "${msUUID}" \
                --type x509 \
                --output "$out/${builtins.baseNameOf file}.esl" \
                "${file}"
            '') msKeys.dbInstallList
          )}
        '';
      msKekEsl =
        let
          sbsiglist = lib.getExe' pkgs.sbsigntool "sbsiglist";
        in
        pkgs.runCommandLocal "secureboot-ms-kek-esl" { } ''
          mkdir -p $out
          ${lib.concatStringsSep "\n" (
            builtins.map (file: ''
              ${sbsiglist} \
                --owner "${msUUID}" \
                --type x509 \
                --output "$out/${builtins.baseNameOf file}.esl" \
                "${file}"
            '') msKeys.kekInstallList
          )}
        '';
    };
  };
}
