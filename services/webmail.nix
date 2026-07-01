{
  lib,
  pkgs,
  config,
  namespaced,
  namespacedCfg,
  foundrixModules,
  ...
}:
let
  cfg = namespacedCfg __curPos;
  python3 = pkgs.python3.withPackages (_: [ ]);

  zitadelCfg = config.foundrix.services.zitadel;
  stalwartCfg = config.foundrix.services.stalwart;
  zitadelProject = zitadelCfg.projects.${cfg.zitadel.projectName};

  clientIdPath = zitadelProject.apps.${cfg.zitadel.appName}.outputPath;
  envFilePath = "/run/webmail/env.file";

  dockerComposeConfig = {
    name = "webmail";
    services.tmail-web = {
      image = cfg.image.destNameTag;
      pull_policy = "never";
      restart = "unless-stopped";
      ports = [ "127.0.0.1:${toString cfg.port}:80" ];
      volumes = [
        "${envFilePath}:/usr/share/nginx/html/assets/env.file:ro"
      ];
    };
  };

  dockerComposeFile = pkgs.writeText "webmail-compose.yml" (builtins.toJSON dockerComposeConfig);

  loadImagesScript = pkgs.writeShellScript "webmail-load-images" ''
    set -e
    imageRef="${cfg.image.imageName}@${cfg.image.imageDigest}"
    if ! ${lib.getExe pkgs.docker} image inspect "$imageRef" &>/dev/null; then
      echo "Loading tmail-web: $imageRef..."
      ${lib.getExe pkgs.docker} load -i ${cfg.image}
    else
      echo "Already loaded tmail-web: $imageRef"
    fi
  '';
in
{
  imports = [
    foundrixModules.services.zitadel
    foundrixModules.services.stalwart
  ];

  options = namespaced __curPos {
    enable = lib.mkEnableOption "TMail webmail client with OIDC authentication";

    domain = lib.mkOption {
      type = lib.types.str;
      description = "Webmail domain (e.g. webmail.example.com)";
      example = "webmail.example.com";
    };

    mailDomain = lib.mkOption {
      type = lib.types.str;
      default = stalwartCfg.domain;
      defaultText = "foundrix.services.stalwart.domain";
      description = "Mail server domain (JMAP backend)";
    };

    ssoDomain = lib.mkOption {
      type = lib.types.str;
      default = zitadelCfg.webDomain;
      defaultText = "foundrix.services.zitadel.webDomain";
      description = "SSO domain for OIDC authentication";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 11080;
      description = "Local port the webmail container listens on";
    };

    # chore: update tmail-web image
    # Check https://hub.docker.com/r/linagora/tmail-web/tags for new versions.
    # Update imageDigest (from the tag's manifest) and hash (nix-prefetch-docker).
    image = lib.mkOption {
      type = lib.types.package;
      default = pkgs.dockerTools.pullImage {
        imageName = "linagora/tmail-web";
        imageDigest = "sha256:f6e838c87ebb33a85eb83d3c8dade52b17193b3394c8679298f8709581d7bcd7";
        hash = "sha256-n86w8105js5xPgi1QXcdd9QY5cIIoV9W4rEAWZ5cvz8=";
        finalImageName = "linagora/tmail-web";
        finalImageTag = "v0.29.9";
      };
      description = "TMail Web Docker image (from dockerTools.pullImage)";
    };

    zitadel = {
      projectName = lib.mkOption {
        type = lib.types.str;
        default = "Mail";
        description = "Zitadel project name (should match stalwart's)";
      };

      appName = lib.mkOption {
        type = lib.types.str;
        default = "webmail";
        description = "Name of the public OIDC app for the webmail client";
      };
    };

    caddy = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Configure a Caddy virtual host for the webmail domain";
      };

      extraTlsConfig = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Extra TLS configuration prepended to the Caddy virtual host";
      };
    };
  };

  config = lib.mkIf cfg.enable {

    # ── Zitadel integration ──────────────────────────────────────────────

    foundrix.services.zitadel.projects.${cfg.zitadel.projectName}.apps.${cfg.zitadel.appName} = {
      type = "public";
      redirectUris = [ "https://${cfg.domain}/login-callback.html" ];
      postLogoutRedirectUris = [ "https://${cfg.domain}/logout-callback.html" ];
    };

    # Tell stalwart about the webmail domain for CORS headers
    foundrix.services.stalwart.webmailDomain = lib.mkDefault cfg.domain;

    # ── Runtime config generation ────────────────────────────────────────

    systemd.services.webmail-config = {
      description = "Generate TMail Web env.file";
      requires = [ zitadelCfg.configureService ];
      after = [ zitadelCfg.configureService ];
      before = [ "webmail.service" ];
      requiredBy = [ "webmail.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = "webmail";
        RuntimeDirectoryMode = "0755";

        ExecStart = pkgs.writeScript "generate-webmail-env" ''
          #!${lib.getExe python3}
          from pathlib import Path

          client_id = Path("${clientIdPath}").read_text().strip()
          Path("${envFilePath}").write_text(
              f"SERVER_URL=https://${cfg.mailDomain}/\n"
              f"DOMAIN_REDIRECT_URL=https://${cfg.domain}\n"
              f"WEB_OIDC_CLIENT_ID={client_id}\n"
              "OIDC_SCOPES=openid,profile,email,offline_access\n"
              "APP_GRID_AVAILABLE=unsupported\n"
              "FCM_AVAILABLE=unsupported\n"
              "IOS_FCM=unsupported\n"
              "FORWARD_WARNING_MESSAGE=\n"
              "PLATFORM=other\n"
              "WS_ECHO_PING=\n"
              "COZY_INTEGRATION=\n"
              "COZY_EXTERNAL_BRIDGE_VERSION=\n"
              "SENTRY_ENABLED=false\n"
              "SENTRY_DSN=\n"
              "SENTRY_ENVIRONMENT=\n"
              "FORCE_EMAIL_QUERY=false\n"
          )
          print(f"Generated env.file with WEB_OIDC_CLIENT_ID={client_id}")
        '';
      };
    };

    # ── Docker service ───────────────────────────────────────────────────

    systemd.services.webmail = rec {
      description = "TMail Web (JMAP webmail)";
      requires = [
        "docker.service"
        "webmail-config.service"
        stalwartCfg.configureService
      ];
      wants = [ "network-online.target" ];
      after = requires ++ wants;
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.docker ];
      serviceConfig = {
        Type = "simple";
        ExecStartPre = loadImagesScript;
        ExecStart = "${lib.getExe pkgs.docker} compose -f ${dockerComposeFile} up --remove-orphans";
        ExecStop = "${lib.getExe pkgs.docker} compose -f ${dockerComposeFile} down";
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };

    # ── Caddy virtual host ───────────────────────────────────────────────

    services.caddy.virtualHosts.${cfg.domain} = lib.mkIf cfg.caddy.enable {
      logFormat = lib.mkForce ''
        level INFO
        output stdout
        format json
      '';
      extraConfig = ''
        ${cfg.caddy.extraTlsConfig}
        header {
          defer
          -Server
          -Via
        }

        header {
          Strict-Transport-Security "max-age=31536000"
          X-Content-Type-Options nosniff
        }

        reverse_proxy 127.0.0.1:${toString cfg.port}
      '';
    };
  };
}
