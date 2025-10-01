{ pkgs, ... }: {
  home.packages = with pkgs; [ qt6Packages.qtdeclarative ];
  programs.vscode.profiles.default.userSettings = {
    "qt-qml.qmlls.useQmlImportPathEnvVar" = true;
    "qt-qml.doNotAskForQmllsDownload" = true;
  };
  programs.vscode.profiles.default.extensions = pkgs.vscode-utils.extensionsFromVscodeMarketplace [
    {
      name = "qt-qml";
      publisher = "TheQtCompany";
      version = "1.5.1";
      sha256 = "sha256-l19OW4lJR8+SxHeLvRzBGtxC+y5seNdOz9jnlK9HDkQ=";
    }
    {
      name = "qt-core";
      publisher = "TheQtCompany";
      version = "1.5.1";
      sha256 = "sha256-0I41cw809oeL5n78TkNKJ+YdFBu237vaNBZuWv3xKn8=";
    }
  ];
}