let
  src = builtins.fetchTree {
    type = "github";
    owner = "ohmyzsh";
    repo = "ohmyzsh";
    # chore: update oh-my-zsh revision to latest commit
    # git ls-remote https://github.com/ohmyzsh/ohmyzsh.git HEAD
    # nix flake prefetch github:ohmyzsh/ohmyzsh/<rev> --json | jq -r .hash
    rev = "2100c630ba4bd67bb48802c3e7da893a4fdaa1a0";
    narHash = "sha256-Y6S7urrtsdUN7A7lgWF2FkIWZpA1HNkjf1eWwfkjzUQ=";
  };
in
{
  plugins = map (name: {
    inherit name src;
    file = "plugins/${name}/${name}.plugin.zsh";
  });
}
