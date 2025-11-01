{
  pkgs,
  lib,
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

      oh-my-zsh-plugin = name: {
        name = name;
        file = "plugins/${name}/${name}.plugin.zsh";
        src = builtins.fetchGit {
          url = "https://github.com/ohmyzsh/ohmyzsh";
          # chore: update oh-my-zsh hash to latest commit
          rev = "eeaf9f89b0e8b10a02f16cb6cdd93779c28eb2ea";
        };
      };
      oh-my-zsh-plugins = names: lib.lists.forEach names oh-my-zsh-plugin;

    in
    {
      environment.pathsToLink = [ "/share/zsh" ];
      programs.zsh.enable = true;
      programs.direnv.enableZshIntegration = true;
      programs.starship = {
        enable = true;
      };
      home-manager = applyHomeManagerUsers cfg.users {
        home.packages = with pkgs; [
          spaceship-prompt
          zsh-history-substring-search
          zsh-completions
          zsh-z
        ];
        programs.zsh = {
          enable = true;
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

          plugins = [
          ]
          ++ (oh-my-zsh-plugins [
            "history"
            "shrink-path"
            "sudo"
            "transfer"
            "z"
          ]);
        };
      };
    };
}
