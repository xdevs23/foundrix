# Hardkernel ODROID-H4 (Intel Alder Lake-N: N97/N100)
#
# This module assumes that nixos-hardware is available.
{
  foundrixModules,
  inputs,
  foundrixIgnoreMissingInputs,
  lib,
  ...
}:
{
  imports =
    lib.optionals (!foundrixIgnoreMissingInputs) (
      with inputs.nixos-hardware.nixosModules;
      [
        common-pc
        common-cpu-intel
        common-pc-ssd
      ]
    )
    ++ [
      foundrixModules.hardware.gpu.intel
    ];
}
