{ pkgs, ... }: {
  environment = {
    systemPackages = with pkgs; [
      vim dust ripgrep exfatprogs strace wget curl
      bash coreutils jq pv socat git dig unzip file tree e2fsprogs
      bc rsync inetutils zip openssh ddrescue gawk less
    ];
    variables = {
      EDITOR = "vim";
      VISUAL = "vim";
      PAGER = "less";
    };
  };
}