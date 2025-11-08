{ nixosModules, ... }:
{
  show-modules =
    let
      green = builtins.fromJSON "\"\\u001b[32;1m\"";
      bold = builtins.fromJSON "\"\\u001b[1m\"";
      reset = builtins.fromJSON "\"\\u001b[0m\"";
      recurse =
        path: set: indent:
        let
          names = builtins.attrNames set;
          lastIndex = (builtins.length names) - 1;
          lines = builtins.genList (
            i:
            let
              name = builtins.elemAt names i;
              value = set.${name};
              isLast = i == lastIndex;
              prefix = if isLast then "└───" else "├───";
              nextIndent = indent + (if isLast then "    " else "│   ");
            in
            if builtins.isAttrs value && !builtins.isFunction value then
              "${green}${indent}${prefix}${reset}${bold}${name}${reset}\n"
              + (recurse (path ++ [ name ]) value nextIndent)
            else
              "${green}${indent}${prefix}${reset}${bold}${name}${reset}"
          ) (lastIndex + 1);
        in
        builtins.concatStringsSep "\n" lines;
      filtered = nixosModules;
    in
    "${bold}foundrixModules${reset}\n" + (recurse [ ] filtered "");
  list-modules =
    let
      recurse =
        path: set:
        builtins.concatStringsSep "\n" (
          builtins.map (
            name:
            let
              value = set.${name};
            in
            if builtins.isAttrs value && !builtins.isFunction value then
              recurse (path ++ [ name ]) value
            else
              builtins.concatStringsSep "." ([ "foundrixModules" ] ++ path ++ [ name ])
          ) (builtins.attrNames set)
        );
      filtered = nixosModules;
    in
    recurse [ ] filtered;
}
