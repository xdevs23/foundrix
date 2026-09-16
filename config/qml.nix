{ pkgs, mkPerUserHomeManagerModule, ... }:
{
  imports = [
    (mkPerUserHomeManagerModule __curPos {
      home.packages = with pkgs; [ qt6Packages.qtdeclarative ];
      programs.vscode.profiles.default.userSettings = {
        "qt-qml.qmlls.useQmlImportPathEnvVar" = true;
        "qt-qml.doNotAskForQmllsDownload" = true;
      };
      programs.vscode.profiles.default.extensions = pkgs.vscode-utils.extensionsFromVscodeMarketplace [
        # chore: update qt-qml extension
        # check https://marketplace.visualstudio.com/items?itemName=TheQtCompany.qt-qml for latest version
        # nix-prefetch-url "https://TheQtCompany.gallery.vsassets.io/_apis/public/gallery/publisher/TheQtCompany/extension/qt-qml/<version>/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage" | nix hash convert --hash-algo sha256 --to sri
        {
          name = "qt-qml";
          publisher = "TheQtCompany";
          version = "1.17.0";
          sha256 = "sha256-4P0v3r1pHgLKR7Jt3Je3kBHSwVZ2djWlxQOmAbTsM/0=";
        }
        # chore: update qt-core extension
        # check https://marketplace.visualstudio.com/items?itemName=TheQtCompany.qt-core for latest version
        # nix-prefetch-url "https://TheQtCompany.gallery.vsassets.io/_apis/public/gallery/publisher/TheQtCompany/extension/qt-core/<version>/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage" | nix hash convert --hash-algo sha256 --to sri
        {
          name = "qt-core";
          publisher = "TheQtCompany";
          version = "1.17.0";
          sha256 = "sha256-knBG17lcrr3NP5sxMtbgG6coiEM//caEeei2NWKfJVk=";
        }
      ];
    })
  ];
}
