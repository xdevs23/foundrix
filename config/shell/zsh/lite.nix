{
  pkgs,
  namespaced,
  namespacedCfg,
  applyHomeManagerUsers,
  mkConfigurableUsersOption,
  ...
}:
{
  options = namespaced __curPos {
    users = mkConfigurableUsersOption {
      description = "Which users to apply zsh.lite to. Defaults to all users.";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;

      ohMyZsh = import ./oh-my-zsh;

    in
    {
      environment.pathsToLink = [ "/share/zsh" ];
      programs.zsh.enable = true;
      programs.direnv.enableZshIntegration = true;
      programs.starship = {
        enable = true;
      };
      home-manager = applyHomeManagerUsers cfg.users (
        { config, ... }:
        {
          home.packages = with pkgs; [
            spaceship-prompt
            zsh-history-substring-search
            zsh-completions
            zsh-z
          ];
          programs.zsh = {
            enable = true;
            # Pin the legacy default (home directory) so the dotDir warning
            # introduced in 26.05 stays silent without changing behavior.
            dotDir = config.home.homeDirectory;
            enableCompletion = true;
            autosuggestion = {
              enable = true;
              highlight = "fg=#cacaca";
            };
            syntaxHighlighting = {
              enable = true;
            };
            autocd = true;

            history = {
              size = 402000;
              save = 400000;
              expireDuplicatesFirst = true;
              extended = true;
              ignoreDups = true;
              share = true;
              ignoreSpace = false;
            };

            historySubstringSearch = {
              enable = true;
              searchDownKey = "$terminfo[kcud1]";
              searchUpKey = "$terminfo[kcuu1]";
            };

            initContent = ''
              source ${pkgs.spaceship-prompt}/share/zsh/themes/spaceship.zsh-theme

              COMPLETION_WAITING_DOTS="true"
            '';

            plugins = ohMyZsh.plugins [
              "history"
              "shrink-path"
              "sudo"
              "transfer"
              "z"
            ];
          };
        }
      );
    };
}
