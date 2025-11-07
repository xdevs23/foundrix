{
  mkPerUserHomeManagerModule,
  lib,
  pkgs,
  namespaced,
  namespacedCfg,
  ...
}:
{
  imports = [
    (mkPerUserHomeManagerModule __curPos {
      home.file = (
        builtins.listToAttrs (
          builtins.concatMap (jdk: [
            {
              name = ".jdks/${lib.versions.major jdk.version}";
              value = {
                source = "${jdk}/lib/openjdk";
              };
            }
            {
              name = ".jdks/${lib.versions.major jdk.version}.intellij";
              value = {
                text = builtins.toJSON rec {
                  vendor = jdk.meta.homepage;
                  product = jdk.pname;
                  flavour = jdk.meta.description;
                  jdk_version_major = lib.versions.major jdk.version;
                  jdk_version = builtins.concatStringsSep "." (lib.take 3 (lib.versions.splitVersion jdk.version));
                  shared_index_aliases = [
                    jdk.name
                    jdk.version
                    "${jdk.pname}-${jdk_version_major}"
                    jdk_version_major
                    jdk_version
                  ];
                };
              };
            }
          ]) (namespacedCfg __curPos).jdkPackages
        )
      );
    })
  ];

  options = namespaced __curPos {
    jdkPackages = lib.mkOption {
      description = "JDK packages to install to home directory in a discoverable fashion";
      type = with lib.types; listOf package;
      default = [ pkgs.jdk ];
    };
  };
}
