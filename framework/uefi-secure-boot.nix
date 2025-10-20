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
    system.build.secureBoot = {
      keys = rec {
        msDbEsl =
          let
            sbsiglist = lib.getExe' pkgs.sbsigntool "sbsiglist";
          in
          pkgs.runCommandLocal "secureboot-ms-db-esl" { } ''
            mkdir -p $out
            ${lib.concatMapStringsSep "\n" (file: ''
              ${sbsiglist} \
                --owner "${msUUID}" \
                --type x509 \
                --output "$out/${builtins.baseNameOf file}.esl" \
                "${file}"
            '') msKeys.dbInstallList}
          '';
        msKekEsl =
          let
            sbsiglist = lib.getExe' pkgs.sbsigntool "sbsiglist";
          in
          pkgs.runCommandLocal "secureboot-ms-kek-esl" { } ''
            mkdir -p $out
            ${lib.concatMapStringsSep "\n" (file: ''
              ${sbsiglist} \
                --owner "${msUUID}" \
                --type x509 \
                --output "$out/${builtins.baseNameOf file}.esl" \
                "${file}"
            '') msKeys.kekInstallList}
          '';
        msCombinedDbEsl = pkgs.runCommandLocal "secureboot-ms-db-combined.esl" { } ''
          cat ${msDbEsl}/*.esl > $out
        '';
        msCombinedKekEsl = pkgs.runCommandLocal "secureboot-ms-kek-combined.esl" { } ''
          cat ${msKekEsl}/*.esl > $out
        '';
      };
      rhUefiShim =
        let
          shimSources =
            {
              "x86_64-linux" = {
                url = "https://kojipkgs.fedoraproject.org/packages/shim/15.8/5/x86_64/shim-x64-15.8-5.x86_64.rpm";
                sha256 = "sha256-JneTMBluKq+EFZ05yXUxDNCV5zw+skqCtcOpX2wNJ5E=";
                shimFile = "shimx64.efi";
                mmFile = "mmx64.efi";
              };
              "aarch64-linux" = {
                url = "https://kojipkgs.fedoraproject.org/packages/shim/15.8/5/aarch64/shim-aa64-15.8-5.aarch64.rpm";
                sha256 = "sha256-ygKJmwFx8F1gQMWHc32KeWISetubACGrD99/21y5BuE=";
                shimFile = "shimaa64.efi";
                mmFile = "mmaa64.efi";
              };
            }
            .${pkgs.stdenv.hostPlatform.system};
        in
        pkgs.stdenv.mkDerivation rec {
          pname = "shim";
          version = "15.8-5";
          src = pkgs.fetchurl {
            url = shimSources.url;
            sha256 = shimSources.sha256;
          };
          nativeBuildInputs = [ pkgs.rpmextract ];
          unpackPhase = ''
            rpmextract $src
          '';
          installPhase = ''
            mkdir -p $out
            cp usr/lib/efi/shim/${version}/EFI/fedora/${shimSources.shimFile} $out/${shimSources.shimFile}
            cp usr/lib/efi/shim/${version}/EFI/fedora/${shimSources.mmFile} $out/${shimSources.mmFile}
          '';
          meta = with pkgs.lib; {
            description = "Microsoft-signed Fedora shim binary";
            homepage = "https://github.com/rhboot/shim";
            license = licenses.gpl3;
            platforms = [
              "x86_64-linux"
              "aarch64-linux"
            ];
          };
        };
    };
  };
}
