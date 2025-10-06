{
  foundrix,
  pkgs,
  ...
}:
{
  environment.systemPackages = builtins.attrValues foundrix.packages.${pkgs.system};
}
