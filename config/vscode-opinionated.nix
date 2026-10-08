# Opinionated vscodium setup
{
  pkgs,
  applyHomeManagerShared,
  ...
}:
{
  home-manager = applyHomeManagerShared {
    programs.vscodium = {
      enable = true;
      mutableExtensionsDir = false;
      profiles.default = {
        enableUpdateCheck = false;
        enableExtensionUpdateCheck = false;

        userSettings = {
          "editor.fontFamily" = "'Aporetic Sans Mono', monospace";
          "editor.lineHeight" = 22;
          "files.autoSave" = "onFocusChange";
          "files.trimTrailingWhitespace" = true;
          "terminal.integrated.fontFamily" = "IosevkaTerm Nerd Font Mono";
          "workbench.startupEditor" = "none";
          "git.terminalAuthentication" = false;
          "github.gitAuthentication" = false;
          "files.enableTrash" = false;
          "git.autoRepositoryDetection" = "openEditors";
          "debug.console.fontFamily" = "IosevkaTerm Nerd Font Mono";
          "editor.inlayHints.enabled" = "off";
          "terminal.integrated.shellIntegration.history" = 100000;
          "terminal.integrated.enablePersistentSessions" = false;
          "editor.rulers" = [ 120 ];
          "workbench.colorCustomizations" = {
            "editorRuler.foreground" = "#242424";
          };
          "terminal.integrated.tabs.enabled" = true;
          "editor.fontSize" = 14;
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

    # The fonts referenced above are not generic families, so ship them rather
    # than hoping the host happens to have them and silently falling back to
    # a proportional font.
    home.packages = [
      pkgs.aporetic
      pkgs.nerd-fonts.iosevka-term
    ];
    fonts.fontconfig.enable = true;
  };
}
