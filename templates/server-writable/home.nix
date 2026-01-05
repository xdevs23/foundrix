{
  applyHomeManagerShared,
  # pkgs is the default package set, from inputs.nixpkgs
  pkgs,
  # pkgsUnstable is the nixos-unstable variant of pkgs, from inputs.nixpkgs-unstable
  #pkgsUnstable,
  # pkgsMaster is the master branch variant of pkgs, from inputs.nixpkgs-master
  #pkgsMaster,
  # If your flake.nix does not provide nixpkgs-unstable and nixpkgs-master, they will be provided
  # by foundrix instead.

  # foundrix itself also provides some packages
  foundrixPkgs,
  # If you need to install something from the flake inputs, you can add inputs here
  #inputs,
  ...
}:
{
  # applyHomeManagerShared sets the same settings for all users.
  # You can also set these for a single user using home-manager.users.<user> = { ... }
  home-manager = applyHomeManagerShared {
    home.language = rec {
      base = "en_US.UTF-8";
      measurement = base;
      monetary = base;
      name = base;
      paper = base;
      time = base;
    };
    # Here's a selection of packages you may find useful. Change to your liking.
    home.packages = with pkgs; [
      jq
      pv
      pwgen
      socat
      git
      curl
      dig
      unzip
      file
      zstd
      tree
      bat
      fd
      brotli
      picocom
      protobuf
      e2fsprogs
      lm_sensors
      fastfetch
      bc
      stress
      subfinder
      smartmontools
      rsync
      iptables
      nftables
      inetutils
      hwloc
      dysk
      openssl
      fd
      nmap
      lz4
      zip
      btop
      foundrixPkgs.json2nix
      foundrixPkgs.nix2json
      foundrixPkgs.git-aliases
      foundrixPkgs.pickrange
      ddrescue
      hdparm
    ];
  };
}
