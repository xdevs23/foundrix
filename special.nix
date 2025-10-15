{ lib, foundrix, ... }:
{
  maybeOr = value: default: if value == null then default else value;
  mkMaybe = value: lib.mkIf (value != null) value;
  mkMaybeDefault = value: lib.mkIf (value != null) (lib.mkDefault value);
  namespaced =
    curPos: options:
    let
      file = curPos.file;
      root = "${foundrix}";

      # Get relative path from root
      relPath = builtins.substring (builtins.stringLength root + 1) (builtins.stringLength file) file;

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
      dirParts = lib.lists.take (builtins.length parts - 1) parts;
      allParts = [ "foundrix" ] ++ dirParts ++ (if baseName == "default" then [ ] else [ baseName ]);

      # Create nested attrset from parts
      mkNested =
        parts: value:
        if parts == [ ] then value else { ${builtins.head parts} = mkNested (builtins.tail parts) value; };
    in
    mkNested allParts options;
}
