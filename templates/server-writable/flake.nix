{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-25.11";
    foundrix = {
      url = "git+https://codeberg.org/xdevs23/foundrix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      foundrix,
      ...
    }@flakeArgs:
    let
      lib = nixpkgs.lib;
      foundrixLib = foundrix.lib;
      forAllSystems = lib.genAttrs lib.systems.flakeExposed;
    in
    foundrix.nixosModules.pluggedInTo flakeArgs rec {
      nixosConfigurations = {
        # Give your OS a name here, or just leave it at nixos-desktop.
        # This is NOT your hostname, but just an identifier.
        # There is no device-specific configuration included here as foundrix orchestrates all that for you.
        # It will discover your devices in the "devices" directory and automatically prepare them as needed.
        # You can customize this by adding `deviceRoots = [ ./devices ./products ];` alongside nixosConfigurations.
        # Ready to use packages will be placed in this flake's packages. For that, consult `nix flake show path:.`
        # Modules added here is equivalent to importing them from configuration.nix.
        # If you only need a single configuration, you can also move the additional modules to your configuration.nix
        # and leave modules here with just configuration.nix.
        nixos-headless = lib.nixosSystem {
          specialArgs = self.nixosModules.foundrixSpecialArgs;
          modules = [
            ./configuration.nix
          ];
        };
      }
      // foundrixLib.deviceFramework.mkDeviceSpecificConfigurations {
        # Here's where you actually configure your hosts.
        # The hostname is the attribute name.
        # The networking.hostName config will be set by the device framework.
        # That allows you to use the same exact configuration on multiple machines while
        # still being able to name them differently.
        my-server = {
          nixosConfiguration = nixosConfigurations.nixos-headless;
          deviceConfiguration = ./devices/my-server; # ← this does not have to be the same as the hostname
          platformModule = foundrix.nixosModules.hardware.platform.x86_64;
        };
      };
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt);
    };
}
