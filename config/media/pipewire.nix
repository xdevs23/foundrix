{
  lib,
  config,
  namespaced,
  namespacedCfg,
  ...
}:
let
  # nixos-unstable deprecated services.pipewire.jack.enable, which sets LD_LIBRARY_PATH for every
  # session, in favor of the pw-jack wrapper.
  jackThroughWrapper = lib.versionAtLeast lib.version "26.10";
in
{
  options = namespaced __curPos {
    support32Bit = lib.mkEnableOption "support for 32 bit";
    pulse = (lib.mkEnableOption "pulse support") // {
      default = true;
    };
    jack = (lib.mkEnableOption "JACK support") // {
      default = true;
      description =
        if jackThroughWrapper then
          "Whether to enable JACK support. JACK programs have to be started through `pw-jack`."
        else
          "Whether to enable JACK support. Every session finds the JACK library of PipeWire through LD_LIBRARY_PATH.";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
    in
    lib.mkMerge [
      {
        services.pipewire = {
          enable = true;
          pulse.enable = cfg.pulse;
          alsa.enable = true;
          alsa.support32Bit = lib.mkDefault cfg.support32Bit;
        };
        security.rtkit.enable = true;
      }
      (lib.mkIf cfg.jack (
        if jackThroughWrapper then
          { environment.systemPackages = [ config.services.pipewire.package.jack ]; }
        else
          { services.pipewire.jack.enable = true; }
      ))
    ];
}
