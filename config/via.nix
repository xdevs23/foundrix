# VIA claims to be GPL-3 but doesn't release source code (unfreeRedistributable in nixpkgs).
# Vial is a fully open-source alternative with the same functionality.
# See: https://get.vial.today/
{ ... }:
{
  imports = [ ./vial.nix ];
  config.warnings = [
    "The 'via' module has been renamed to 'vial'. VIA claims to be GPL-3 but doesn't release source code, while Vial is fully open-source. Please update your configuration to use 'foundrix.config.vial' instead of 'foundrix.config.via'."
  ];
}
