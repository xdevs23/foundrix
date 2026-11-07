let
  src = builtins.fetchTree {
    type = "github";
    owner = "ohmyzsh";
    repo = "ohmyzsh";
    # chore: update oh-my-zsh revision to latest commit
    # git ls-remote https://github.com/ohmyzsh/ohmyzsh.git HEAD
    # nix flake prefetch github:ohmyzsh/ohmyzsh/<rev> --json | jq -r .hash
    rev = "cca3bdfbef8c52ef8939ce7911ff68852b949daa";
    narHash = "sha256-RwuU3bRMxRtdH+TbETZRIHcQYyXaItR4H7ufWL3U4wY=";
  };
in
{
  plugins = map (
    name:
    let
      dir = "${src}/plugins/${name}";
    in
    if builtins.pathExists dir then
      {
        inherit name;
        src = dir;
        file = "${name}.plugin.zsh";
      }
    else
      throw "oh-my-zsh at ${src.rev} does not have a plugin named \"${name}\""
  );
}
