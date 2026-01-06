# Import all trait modules to ensure options are always available.
# Uses direct imports to avoid circular dependency with common/.
{ ... }:
{
  imports = [
    ./filesystem.nix
    ./home-manager.nix
  ];
}
