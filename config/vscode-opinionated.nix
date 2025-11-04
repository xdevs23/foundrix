# Opinionated vscodium setup
{ pkgs, applyHomeManagerShared, ... }:
{
  home-manager = applyHomeManagerShared {
    programs.vscode = {
      enable = true;
      package = pkgs.vscodium;
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
  };
}
