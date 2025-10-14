{ lib, ... }: {
  maybeOr = value: default: if value == null then default else value;
  mkMaybe = value: lib.mkIf (value != null) value;
  mkMaybeDefault = value: lib.mkIf (value != null) (lib.mkDefault value);
}