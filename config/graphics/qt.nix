{ mkPerUserHomeManagerModule, ... }:
{
  imports = [
    (mkPerUserHomeManagerModule __curPos {
      qt = {
        enable = true;
      };
    })
  ];
}
