{
  lib,
  namespaced,
  namespacedCfg,
  ...
}:
{
  options = namespaced __curPos {
    support32Bit = lib.mkEnableOption "support for 32 bit";
    pulse = (lib.mkEnableOption "pulse support") // {
      default = true;
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
    in
    {
      services.pipewire = {
        enable = true;
        pulse.enable = cfg.pulse;
        alsa.enable = true;
        alsa.support32Bit = lib.mkDefault cfg.support32Bit;
      };
      security.rtkit.enable = true;
    };
}
