let
  src = builtins.fetchGit {
    url = "https://github.com/ohmyzsh/ohmyzsh";
    # chore: update oh-my-zsh revision to latest commit
    # git ls-remote https://github.com/ohmyzsh/ohmyzsh.git HEAD
    rev = "2100c630ba4bd67bb48802c3e7da893a4fdaa1a0";
  };
in
{
  plugins = map (name: {
    inherit name src;
    file = "plugins/${name}/${name}.plugin.zsh";
  });
}
