# Opinionated vscodium setup
{
  pkgs,
  lib,
  applyHomeManagerShared,
  ...
}:
let
  # Shared, package-agnostic configuration. On 26.05+ home-manager exposes a
  # dedicated `programs.vscodium` module that writes to VSCodium's own paths;
  # before that, VSCodium is configured through `programs.vscode` with the
  # package overridden. The body is identical between the two.
  settings = {
    enable = true;
    mutableExtensionsDir = false;
    profiles.default = {
      enableUpdateCheck = false;
      enableExtensionUpdateCheck = false;

      userSettings = {
        "editor.fontFamily" = "'Iosevka Comfy', monospace";
        "editor.lineHeight" = 22;
        "files.autoSave" = "onFocusChange";
        "files.trimTrailingWhitespace" = true;
        "terminal.integrated.fontFamily" = "Hasklug Nerd Font Mono";
        "workbench.startupEditor" = "none";
        "git.terminalAuthentication" = false;
        "github.gitAuthentication" = false;
        "files.enableTrash" = false;
        "git.autoRepositoryDetection" = "openEditors";
        "debug.console.fontFamily" = "Hasklug Nerd Font Mono";
        "editor.inlayHints.enabled" = "off";
        "terminal.integrated.shellIntegration.history" = 100000;
        "terminal.integrated.enablePersistentSessions" = false;
        "editor.rulers" = [ 120 ];
        "workbench.colorCustomizations" = {
          "editorRuler.foreground" = "#242424";
        };
        "terminal.integrated.tabs.enabled" = true;
        "editor.fontSize" = 13;
        "git.openRepositoryInParentFolders" = "never";
        "nix.enableLanguageServer" = true;
        "nix.serverPath" = "nixd";
        "diffEditor.ignoreTrimWhitespace" = false;
        "workbench.sideBar.location" = "right";
      };
      extensions = with pkgs.vscode-extensions; [
        tamasfe.even-better-toml
        jnoortheen.nix-ide
        rust-lang.rust-analyzer
        naumovs.color-highlight
        ziglang.vscode-zig
        mkhl.direnv
        ms-azuretools.vscode-docker
        vadimcn.vscode-lldb
        matthewpi.caddyfile-support
      ];
    };
  };

  useVscodiumModule = lib.versionAtLeast lib.version "26.04";
in
{
  home-manager = applyHomeManagerShared {
    programs.vscodium = lib.mkIf useVscodiumModule settings;
    programs.vscode = lib.mkIf (!useVscodiumModule) (settings // { package = pkgs.vscodium; });
  };
}
