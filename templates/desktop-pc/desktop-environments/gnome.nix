{ foundrixModules, ... }:
{
  imports = [
    foundrixModules.components.desktop-environments.gnome
    foundrixModules.config.graphics.gtk-dark
    foundrixModules.config.graphics.themes.adwaita-dark
  ];

  # As soon as you try cross-compiling gnome, it will fail with broken totem
  device.crossCompile = false;
}
