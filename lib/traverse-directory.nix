{ lib, ... }:
{
  directory,
  includeDirectories ? false, # Whether to include directories themselves as entries
  includeDefaultNix ? false, # Whether to exclude default.nix files
  recurse ? true,
  format ? "attrset", # "attrset" or "list"
}:
let
  processDir =
    dir: relativePath:
    let
      entries = builtins.readDir dir;
      processEntry =
        name: type:
        let
          path = dir + "/${name}";
          newRelativePath = if relativePath == "" then name else "${relativePath}/${name}";
          baseName = lib.removeSuffix ".nix" name;
          attrName =
            if relativePath == "" then
              baseName
            else
              lib.replaceStrings [ "/" ] [ "-" ] (lib.removeSuffix ".nix" newRelativePath);
        in
        if type == "directory" then
          (if recurse then processDir path newRelativePath else [ ])
          ++ (
            if includeDirectories then
              [
                {
                  name = if relativePath == "" then name else newRelativePath;
                  path = path;
                  attrName = if relativePath == "" then name else lib.replaceStrings [ "/" ] [ "-" ] newRelativePath;
                }
              ]
            else
              [ ]
          )
        else if
          type == "regular" && lib.hasSuffix ".nix" name && (name != "default.nix" || includeDefaultNix)
        then
          [
            {
              name = newRelativePath;
              path = path;
              attrName = attrName;
            }
          ]
        else
          [ ];
    in
    lib.concatLists (lib.mapAttrsToList processEntry entries);

  results = processDir directory "";
in
if format == "list" then
  results
# attrset
else
  lib.listToAttrs (
    map (item: {
      name = item.attrName;
      value = item.path;
    }) results
  )
