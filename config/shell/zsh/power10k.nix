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
      description = "Which users to apply power10k to. Defaults to all users.";
    };
    osIconCodepoint = lib.mkOption {
      type = lib.types.str;
      default = "f313";
      description = ''
        Choose a logo from
        https://github.com/Lukas-W/font-logos?tab=readme-ov-file#usage
        and use the part of the codepoint after 0x
      '';
    };
    colors = {
      osIconBackground = lib.mkOption {
        type = lib.types.str;
        default = "#233253";
        description = "Background color of OS icon";
      };
      hostBackground = lib.mkOption {
        type = lib.types.str;
        default = "#26375B";
        description = "Background color of host string";
      };
      userBackground = lib.mkOption {
        type = lib.types.str;
        default = "#2A3D64";
        description = "Background color of user string";
      };
      dirBackground = lib.mkOption {
        type = lib.types.str;
        default = "#2E436E";
        description = "Background color of directory string";
      };
      dirAnchorBackground = lib.mkOption {
        type = lib.types.str;
        default = "#334A79";
        description = "Background color of directory anchor";
      };
      osIconForeground = lib.mkOption {
        type = lib.types.str;
        default = "#7EBAE4";
        description = "Text color of OS icon";
      };
      hostForeground = lib.mkOption {
        type = lib.types.str;
        default = "#87BFE6";
        description = "Text color of host string";
      };
      userForeground = lib.mkOption {
        type = lib.types.str;
        default = "#8FC3E8";
        description = "Text color of user string";
      };
      dirForeground = lib.mkOption {
        type = lib.types.str;
        default = "#9FCCEB";
        description = "Text color of directory string";
      };
      dirAnchorForeground = lib.mkOption {
        type = lib.types.str;
        default = "#BFDDF2";
        description = "Text color of directory anchor";
      };
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;

      zshCacheDir = "\${XDG_CACHE_HOME:-$HOME/.cache}/zsh";
      ohMyZsh = import ./oh-my-zsh;

    in
    {
      environment.pathsToLink = [ "/share/zsh" ];
      programs.zsh.enable = true;
      programs.direnv.enableZshIntegration = true;

      home-manager = applyHomeManagerUsers cfg.users (
        { config, ... }:
        {
          home.packages = with pkgs; [
            zsh-history-substring-search
            zsh-completions
            zsh-z
            pay-respects
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

            initContent =
              let
                p10kConfigFile = ./.p10k.zsh;
              in
              ''
                mkdir -p "${zshCacheDir}"
                ZSH_CACHE_DIR="${zshCacheDir}"
                DISABLE_AUTO_UPDATE="true"
                DISABLE_UPDATE_PROMPT="true"
                COMPLETION_WAITING_DOTS="true"
                alias ll='ls -alF'
                alias la='ls -A'
                alias l='ls -CF'

                # Skip p10k on TTY or low-color terminals - use simple prompt instead
                if [[ "$(tty)" == *"/tty"* ]] || [[ $(tput colors 2>/dev/null) -lt 256 ]]; then
                  autoload -Uz promptinit && promptinit
                  PROMPT='%F{green}%n@%m%f:%F{blue}%~%f$ '
                else
                  source "${p10kConfigFile}"
                  if [[ $COLORTERM =~ ^(truecolor|24bit)$ ]]; then
                    typeset -g POWERLEVEL9K_CUSTOM_OS_ICON_BACKGROUND="${cfg.colors.osIconBackground}"
                    typeset -g POWERLEVEL9K_HOST_BACKGROUND="${cfg.colors.hostBackground}"
                    typeset -g POWERLEVEL9K_USER_BACKGROUND="${cfg.colors.userBackground}"
                    typeset -g POWERLEVEL9K_DIR_BACKGROUND="${cfg.colors.dirBackground}"
                    typeset -g POWERLEVEL9K_DIR_ANCHOR_BACKGROUND="${cfg.colors.dirAnchorBackground}"

                    typeset -g POWERLEVEL9K_CUSTOM_OS_ICON_FOREGROUND="${cfg.colors.osIconForeground}"
                    typeset -g POWERLEVEL9K_HOST_FOREGROUND="${cfg.colors.hostForeground}"
                    typeset -g POWERLEVEL9K_USER_FOREGROUND="${cfg.colors.userForeground}"
                    typeset -g POWERLEVEL9K_DIR_FOREGROUND="${cfg.colors.dirForeground}"
                    typeset -g POWERLEVEL9K_DIR_ANCHOR_FOREGROUND="${cfg.colors.dirAnchorForeground}"

                    typeset -g POWERLEVEL9K_CUSTOM_OS_ICON="echo $'\u${cfg.osIconCodepoint}'"
                  fi
                  source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
                fi
                eval "$(pay-respects zsh --nocnf)"
                [[ -z "$ZSH_LAST_WORKING_DIRECTORY" ]] || return
                [[ "$PWD" == "$HOME" ]] || return

                if lwd 2>/dev/null; then
                  ZSH_LAST_WORKING_DIRECTORY=1
                fi
              '';

            plugins = ohMyZsh.plugins [
              "git"
              "adb"
              "battery"
              "colorize"
              "cp"
              "emoji"
              "fancy-ctrl-z"
              "fd"
              "git-flow"
              "github"
              "gitignore"
              "gnu-utils"
              "golang"
              "history"
              "httpie"
              "jsontools"
              "jump"
              "last-working-dir"
              "lol"
              "man"
              "mosh"
              "nmap"
              "node"
              "pep8"
              "pip"
              "pj"
              "ripgrep"
              "rsync"
              "shrink-path"
              "sudo"
              "themes"
              "transfer"
              "yarn"
              "z"
            ];
          };
        }
      );
    };
}
