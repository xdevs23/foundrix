{
  applyHomeManagerShared,
  # pkgs is the default package set, from inputs.nixpkgs
  pkgs,
  # pkgsUnstable is the nixos-unstable variant of pkgs, from inputs.nixpkgs-unstable
  pkgsUnstable,
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
  home-manager = applyHomeManagerShared rec {
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
      # Example for using a flake input:
      #inputs.zen-browser.packages.${pkgs.system}.beta
      jq
      pv
      pwgen
      socat
      pavucontrol
      playerctl
      git
      curl
      cliphist
      wl-clipboard
      wl-clipboard-x11
      easyeffects
      mangohud
      celluloid
      dig
      unzip
      file
      zstd
      tree
      bat
      fd
      brotli
      picocom
      chromium
      protobuf
      e2fsprogs
      lm_sensors
      fastfetch
      pkgsUnstable.nixd
      nixpkgs-fmt
      bc
      imagemagick
      thunderbird
      evince
      stress
      subfinder
      smartmontools
      rsync
      vlc
      p7zip
      iptables
      nftables
      inetutils
      simple-scan
      hwloc
      dysk
      openssl
      fd
      nmap
      lz4
      zip
      mpv
      btop
      foundrixPkgs.json2nix
      foundrixPkgs.nix2json
      foundrixPkgs.git-aliases
      foundrixPkgs.pickrange
      gimp3
      pinta
      krita
      ddrescue
      hdparm
      gnome-boxes
      libreoffice-fresh
      audacity
    ];
    xdg = {
      mimeApps.associations = {
        added = {
          "application/pdf" = "org.gnome.Evince.desktop";
          #"..." = "..."
        };
      };
      mimeApps.defaultApplications = xdg.mimeApps.associations.added;
    };
  };
}
