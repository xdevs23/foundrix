{ pkgs, ... }:
{
  home.packages = with pkgs; [ qt6Packages.qtdeclarative ];
  programs.vscode.profiles.default.userSettings = {
    "qt-qml.qmlls.useQmlImportPathEnvVar" = true;
    "qt-qml.doNotAskForQmllsDownload" = true;
  };
  programs.vscode.profiles.default.extensions = pkgs.vscode-utils.extensionsFromVscodeMarketplace [
    {
      name = "qt-qml";
      publisher = "TheQtCompany";
      version = "1.9.0";
      sha256 = "sha256-cWS3xUAbPiH/Mqohs0reWNyfMLiSO7tXdIp7/GbTysw=";
    }
    {
      name = "qt-core";
      publisher = "TheQtCompany";
      version = "1.9.0";
      sha256 = "sha256-IpqsDfhx9UIA3jm/BkPW9mzMkr+muvvhak/wPZb8HQA=";
    }
  ];
}
