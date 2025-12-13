{
  lib,
  foundrix,
  currentFlake,
  ...
}:
rec {
  maybeOr = value: default: if value == null then default else value;
  mkMaybe = value: lib.mkIf (value != null) value;
  mkMaybeDefault = value: lib.mkIf (value != null) (lib.mkDefault value);
  namespaced =
    curPos: options:
    let
      file = curPos.file;
      foundrixRoot = toString foundrix;
      currentFlakeRoot = toString currentFlake;

      # Check if file is within foundrix
      isInFoundrix = lib.hasPrefix foundrixRoot file;

      root = if isInFoundrix then foundrixRoot else currentFlakeRoot;

      # Get relative path from root
      relPath = builtins.substring (
        builtins.stringLength (toString root) + 1
      ) (builtins.stringLength file) file;

      # Split into parts
      parts = builtins.filter (x: x != "") (lib.splitString "/" relPath);

      # Remove .nix from last element
      fileName = builtins.elemAt parts (builtins.length parts - 1);
      baseName =
        if builtins.match "(.*)\.nix" fileName != null then
          builtins.head (builtins.match "(.*)\.nix" fileName)
        else
          fileName;

      # Build path parts: directory parts + filename (unless it's "default")
      # For foundrix modules, prefix with "foundrix"; for user configs, no prefix
      dirParts = lib.lists.take (builtins.length parts - 1) parts;
      prefix = if isInFoundrix then [ "foundrix" ] else [ "custom" ];
      allParts = prefix ++ dirParts ++ (if baseName == "default" then [ ] else [ baseName ]);

      # Create nested attrset from parts
      mkNested =
        parts: value:
        if parts == [ ] then value else { ${builtins.head parts} = mkNested (builtins.tail parts) value; };
    in
    mkNested allParts options;
  applyHomeManagerShared = applyHomeManagerUsers null;
  applyHomeManagerUsers =
    users: cfg:
    if users == null then
      {
        sharedModules = [ cfg ];
      }
    else
      {
        users = lib.genAttrs users (username: cfg);
      };
  mkPerUserHomeManagerModule =
    curPos: config:
    {
      mkConfigurableUsersOption,
      applyHomeManagerUsers,
      namespaced,
      namespacedCfg,
      ...
    }:
    {
      options = namespaced curPos {
        users = mkConfigurableUsersOption {
          description = "Which users to apply this configuration to. Defaults to all users.";
        };
      };

      config =
        let
          cfg = namespacedCfg curPos;
        in
        {
          home-manager = applyHomeManagerUsers cfg.users config;
        };
    };

}
