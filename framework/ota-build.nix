{
  pkgs,
  config,
  lib,
  namespaced,
  namespacedCfg,
  ...
}:
{
  options = namespaced __curPos {
    artifacts = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            source = lib.mkOption {
              type = lib.types.path;
              description = "Source path of the artifact";
            };
            compressionLevel = lib.mkOption {
              type = lib.types.int;
              default = 4;
              description = "Compression level for compressor";
            };
            compressedExtension = lib.mkOption {
              type = lib.types.str;
              default = "gz";
            };
            compressor = lib.mkOption {
              type = lib.types.functionTo lib.types.package;
              default =
                {
                  name,
                  inputFile,
                  compressionLevel,
                }:
                pkgs.runCommand name
                  {
                    allowSubstitutes = false;
                    dontFixup = true;
                    nativeBuildInputs = [ pkgs.pigz ];
                  }
                  ''
                    pigz -${toString compressionLevel} -c ${inputFile} > $out
                  '';
              description = "Compressor to use, defaults to pigz";
            };
          };
        }
      );
      default = { };
      description = "Artifacts to include in the OTA update";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
      sys = config.system;
      artifacts = cfg.artifacts;
      imageId = if sys.image.id != null then sys.image.id else config.boot.uki.name;
    in
    {
      system.build.otaUpdate =
        pkgs.runCommand "update-${imageId}-${sys.image.version}"
          {
            allowSubstitutes = false;
            dontFixup = true;
            nativeBuildInputs = [ pkgs.coreutils ];
          }
          ''
            mkdir -p $out
            ${lib.concatStringsSep "\n" (
              lib.mapAttrsToList (name: artifact: ''
                cp --reflink=auto ${artifact.source} $out/${name}
              '') artifacts
            )}
            ${lib.optionalString (artifacts != { }) ''
              cd $out
              ${lib.concatStringsSep "\n" (
                lib.mapAttrsToList (name: artifact: ''
                  sha256sum ${name} >> SHA256SUMS
                '') artifacts
              )}
            ''}
          '';

      system.build.compressedOtaUpdate =
        pkgs.runCommand "compressed-update-${imageId}-${sys.image.version}"
          {
            allowSubstitutes = false;
            dontFixup = true;
            nativeBuildInputs = [ pkgs.coreutils ];
          }
          ''
            mkdir -p $out
            ${lib.concatStringsSep "\n" (
              lib.mapAttrsToList (
                name: artifact:
                let
                  compressed = artifact.compressor {
                    name = "compressed-${name}.${artifact.compressedExtension}";
                    inputFile = artifact.source;
                    compressionLevel = artifact.compressionLevel;
                  };
                in
                ''
                  cp --reflink=auto ${compressed} $out/${name}.${artifact.compressedExtension}
                ''
              ) artifacts
            )}
            ${lib.optionalString (artifacts != { }) ''
              cd $out
              ${lib.concatStringsSep "\n" (
                lib.mapAttrsToList (name: artifact: ''
                  sha256sum ${name}.${artifact.compressedExtension} >> SHA256SUMS
                '') artifacts
              )}
            ''}
          '';
    };
}
