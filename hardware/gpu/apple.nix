{ namespaced, lib, ... }:
{
  options = namespaced __curPos {
    isSupported = lib.mkOption {
      type = lib.types.bool;
      description = "Whether Apple GPU is supported";
      readOnly = true;
      default = true;
    };
  };
}
