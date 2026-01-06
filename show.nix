{ nixosModules, ... }:
let
  # ANSI color codes
  green = builtins.fromJSON "\"\\u001b[32;1m\"";
  red = builtins.fromJSON "\"\\u001b[31m\"";
  cyan = builtins.fromJSON "\"\\u001b[36m\"";
  dim = builtins.fromJSON "\"\\u001b[2m\"";
  gray = builtins.fromJSON "\"\\u001b[90m\""; # bright black - more visible than dim
  bold = builtins.fromJSON "\"\\u001b[1m\"";
  reset = builtins.fromJSON "\"\\u001b[0m\"";

  # Trait type constants (enum variants and descriptions)
  traitTypes = import ./framework/traits/types.nix;

  # Check if a trait is an enum type (has variants in traitTypes)
  isEnumTrait = category: name: traitTypes ? ${category} && traitTypes.${category} ? ${name};

  # Common function to show traits
  # enabledOnly: if true, only show enabled traits; if false, show all
  mkShowTraits =
    enabledOnly:
    { config, options }:
    let
      traits = config.foundrix.traits or { };
      traitOptions = options.foundrix.traits or { };

      # Collect traits using options as source of truth
      collectTraits =
        category: categoryOptions:
        builtins.filter (x: x != null) (
          builtins.attrValues (
            builtins.mapAttrs (
              name: opt:
              let
                isEnum = isEnumTrait category name;
                # Get value from config (graceful non-existence)
                value = traits.${category}.${name} or (if isEnum then null else false);
                # For booleans: enabled = true, for enums: enabled = non-null
                enabled = if isEnum then value != null else value == true;
                # Get description from the option definition
                description = opt.description or "No description";
              in
              if enabledOnly && !enabled then
                null
              else
                {
                  inherit category name enabled isEnum value description;
                  variants =
                    if isEnum then
                      traitTypes.${category}.${name}
                    else
                      null;
                  variantDescriptions =
                    if isEnum then
                      (traitTypes.descriptions.${category}.${name} or { })
                    else
                      null;
                }
            ) categoryOptions
          )
        );

      collectedTraits = builtins.concatLists (
        builtins.attrValues (builtins.mapAttrs collectTraits traitOptions)
      );

      formatTrait =
        trait:
        if trait.isEnum then
          formatEnumTrait trait
        else
          formatBoolTrait trait;

      formatBoolTrait =
        { category, name, enabled, description, ... }:
        let
          indicator = if enabled then "${green}●${reset}" else "${red}○${reset}";
          status = if enabled then "" else " ${dim}(disabled)${reset}";
        in
        "${indicator} ${bold}${category}.${name}${reset}${status}\n  ${gray}${description}${reset}";

      formatEnumTrait =
        {
          category,
          name,
          enabled,
          value,
          description,
          variants,
          variantDescriptions,
          ...
        }:
        let
          indicator = if enabled then "${green}●${reset}" else "${red}○${reset}";
          typeLabel = " ${dim}[enum]${reset}";
          variantNames = builtins.attrNames variants;
          formatVariant =
            variantName:
            let
              variantValue = variants.${variantName};
              isSelected = value == variantValue;
              # All variants dim/gray when trait is disabled, otherwise green for selected
              variantIndicator =
                if !enabled then "${dim}○${reset}"
                else if isSelected then "${green}●${reset}"
                else "${dim}○${reset}";
              variantDesc = variantDescriptions.${variantName} or "";
              # Description is dim when trait is disabled, gray otherwise
              descColor = if enabled then gray else dim;
              descPart = if variantDesc != "" then " ${descColor}(${variantDesc})${reset}" else "";
              # Variant name is dim when trait is disabled, normal otherwise
              variantNameFormatted = if enabled then variantName else "${dim}${variantName}${reset}";
            in
            "  ${variantIndicator} ${variantNameFormatted}${descPart}";
          variantLines = builtins.concatStringsSep "\n" (map formatVariant variantNames);
        in
        "${indicator} ${bold}${category}.${name}${reset}${typeLabel}\n  ${gray}${description}${reset}\n${variantLines}";

      title = if enabledOnly then "Enabled Traits" else "All Traits";
      emptyMsg = if enabledOnly then "No traits enabled" else "No traits defined";
    in
    if collectedTraits == [ ] then
      "${dim}${emptyMsg}${reset}\n"
    else
      "${bold}${cyan}${title}${reset}\n\n" + builtins.concatStringsSep "\n\n" (map formatTrait collectedTraits) + "\n";
in
{
  # Show enabled traits for a configuration
  show-traits = mkShowTraits true;

  # Show all traits (enabled and disabled) for a configuration
  show-all-traits = mkShowTraits false;

  show-modules =
    let
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
