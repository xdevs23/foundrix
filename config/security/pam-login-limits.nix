{
  security.pam.loginLimits = [
    {
      type = "hard";
      domain = "*";
      item = "nofile";
      value = "1048576";
    }
  ];
}
