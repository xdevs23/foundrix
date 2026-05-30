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
  zitadelProject = zitadelCfg.projects.${cfg.zitadel.projectName};

  adminPasswordPath = config.foundrix.services.secrets.stalwart-admin-password.path;
  cookieSecretPath = config.foundrix.services.secrets.oauth2-proxy-cookie-secret.path;
  oauth2ProxyCredsPath = zitadelProject.apps.${cfg.zitadel.adminAppName}.outputPath;
  selfServiceClientIdPath = zitadelProject.apps.${cfg.zitadel.selfServiceAppName}.outputPath;
  authEnvFile = "/run/stalwart-auth/oauth2-proxy.env";

  selfServiceDir = ./stalwart-self-service;

  desiredState = builtins.toJSON {
    stalwartUrl = "http://127.0.0.1:${toString cfg.httpPort}";
    inherit adminPasswordPath;
    domain = builtins.head (builtins.attrNames zitadelCfg.orgDomains);
    publicUrl = "'https://${cfg.domain}'";
  };

  configureScript = ./stalwart-configure.ts;
in
{
  imports = [
    foundrixModules.services.zitadel
    foundrixModules.services.secrets
  ];

  options = namespaced __curPos {
    enable = lib.mkEnableOption "Stalwart mail server with automated first-time setup";

    domain = lib.mkOption {
      type = lib.types.str;
      description = "Mail server domain (e.g. mail.example.com)";
      example = "mail.example.com";
    };

    orgDomain = lib.mkOption {
      type = lib.types.str;
      default = zitadelCfg.adminOrg;
      defaultText = "foundrix.services.zitadel.adminOrg";
      description = "Organization domain for email addresses (e.g. example.com)";
    };

    ssoDomain = lib.mkOption {
      type = lib.types.str;
      default = zitadelCfg.webDomain;
      defaultText = "foundrix.services.zitadel.webDomain";
      description = "SSO domain for OIDC authentication";
    };

    webmailDomain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Webmail domain for CORS headers (e.g. webmail.example.com)";
    };

    package = lib.mkPackageOption pkgs "stalwart" { };

    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 8443;
      description = "Internal HTTP port for admin UI, JMAP, and autoconfig";
    };

    acme = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Stalwart's built-in ACME for SMTP TLS certificates";
      };

      directory = lib.mkOption {
        type = lib.types.str;
        default = "https://acme.zerossl.com/v2/DV90";
        description = "ACME directory URL";
      };

      contactEmail = lib.mkOption {
        type = lib.types.str;
        default = "admin@${cfg.orgDomain}";
        defaultText = "admin@<orgDomain>";
        description = "Contact email for ACME certificate requests";
      };

      eabCredentialsFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Path to EAB credentials file containing:
            EAB_KID=your-key-id
            EAB_HMAC_KEY=your-hmac-key
        '';
      };
    };

    zitadel = {
      projectName = lib.mkOption {
        type = lib.types.str;
        default = "Mail";
        description = "Zitadel project name for mail-related OIDC apps";
      };

      adminAppName = lib.mkOption {
        type = lib.types.str;
        default = "stalwart-admin";
        description = "Name of the confidential OIDC app for admin authentication";
      };

      selfServiceAppName = lib.mkOption {
        type = lib.types.str;
        default = "mail-self-service";
        description = "Name of the public OIDC app for the self-service page";
      };

      adminRoleKey = lib.mkOption {
        type = lib.types.str;
        default = "mail-admin";
        description = "Zitadel project role key that grants Stalwart admin access";
      };
    };

    caddy = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Configure Caddy virtual hosts for the mail domain";
      };

      extraTlsConfig = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Extra TLS configuration prepended to Caddy virtual hosts (e.g. custom CA)";
      };
    };

    selfService = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable the app-password self-service page";
      };
    };

    configureService = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "stalwart-configure.service";
      description = "Systemd unit that completes once Stalwart is fully configured";
    };
  };

  config = lib.mkIf cfg.enable {

    # ── Zitadel integration ──────────────────────────────────────────────

    foundrix.services.zitadel.projects.${cfg.zitadel.projectName} = {
      apps.${cfg.zitadel.adminAppName} = {
        type = "confidential";
        redirectUris = [ "https://${cfg.domain}/oauth2/callback" ];
      };

      apps.${cfg.zitadel.selfServiceAppName} = lib.mkIf cfg.selfService.enable {
        type = "public";
        redirectUris = [
          "https://${cfg.domain}/"
          "https://${cfg.domain}/self-service"
        ];
        postLogoutRedirectUris = [
          "https://${cfg.domain}/"
          "https://${cfg.domain}/self-service"
        ];
      };

      roles.${cfg.zitadel.adminRoleKey}.displayName = "Mail Administrator";

      userGrants.${zitadelCfg.admin.username} = [ cfg.zitadel.adminRoleKey ];
    };

    # ── Secrets ──────────────────────────────────────────────────────────

    foundrix.services.secrets = {
      stalwart-admin-password = {
        persistent = true;
        length = 24;
        symbols = true;
      };
      oauth2-proxy-cookie-secret = {
        persistent = true;
        length = 32;
        binary = true;
      };
    };

    # ── Stalwart mail service ────────────────────────────────────────────

    services.stalwart = {
      enable = true;
      package = cfg.package;

      credentials = {
        admin-password = adminPasswordPath;
      };

      settings = lib.recursiveUpdate {
        server.hostname = cfg.domain;

        server.listener.smtp = {
          bind = [ "[::]:25" ];
          protocol = "smtp";
        };
        server.listener.http = {
          bind = [ "127.0.0.1:${toString cfg.httpPort}" ];
          protocol = "http";
        };

        directory.zitadel = {
          type = "oidc";
          store = "db";
          endpoint.url = "https://${cfg.ssoDomain}/oidc/v1/userinfo";
          endpoint.method = "userinfo";
          fields.email = "email";
          fields.username = "preferred_username";
          fields.full-name = "name";
        };
        storage.directory = "zitadel";

        authentication.fallback-admin = {
          user = "admin";
          secret = "%{file:/run/credentials/stalwart.service/admin-password}%";
        };

        session.rcpt.catch-all = true;
        session.rcpt.sub-addressing = true;
        server.listener.submissions = {
          bind = [ "[::]:465" ];
          protocol = "smtp";
          tls.implicit = true;
        };
        server.listener.imaptls = {
          bind = [ "[::]:993" ];
          protocol = "imap";
          tls.implicit = true;
        };
      } (
        lib.optionalAttrs cfg.acme.enable {
          acme.default-acme = {
            directory = cfg.acme.directory;
            contact = [ "mailto:${cfg.acme.contactEmail}" ];
            domains = [ cfg.domain ];
            challenge = "http-01";
            "eab.kid" = "%{env:EAB_KID}%";
            "eab.hmac-key" = "%{env:EAB_HMAC_KEY}%";
            default = true;
          };
        }
      );
    };

    systemd.tmpfiles.settings."stalwart-state" = {
      "/var/lib/stalwart".Z = {
        mode = "0750";
        user = "stalwart";
        group = "stalwart";
      };
    };

    systemd.services.stalwart = lib.mkMerge [
      {
        requires = [
          config.foundrix.services.secrets.stalwart-admin-password.service
        ];
        after = [
          config.foundrix.services.secrets.stalwart-admin-password.service
        ];
      }
      (lib.mkIf (cfg.acme.enable && cfg.acme.eabCredentialsFile != null) {
        serviceConfig.EnvironmentFile = [ cfg.acme.eabCredentialsFile ];
      })
    ];

    # ── First-time setup ─────────────────────────────────────────────────

    systemd.services.stalwart-setup-config = {
      description = "Generate Stalwart setup config";
      before = [ "stalwart-configure.service" ];
      requiredBy = [ "stalwart-configure.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = "stalwart-setup";
        RuntimeDirectoryMode = "0750";

        ExecStart = pkgs.writeScript "generate-stalwart-config" ''
          #!${lib.getExe python3}
          from pathlib import Path
          Path("/run/stalwart-setup/desired-state.json").write_text(${builtins.toJSON desiredState})
        '';
      };
    };

    systemd.services.stalwart-configure = {
      description = "Configure Stalwart mail server";
      requires = [
        "stalwart.service"
        zitadelCfg.configureService
      ];
      after = [
        "stalwart.service"
        zitadelCfg.configureService
      ];
      requiredBy = lib.optionals cfg.caddy.enable [ "caddy.service" ];
      before = lib.optionals cfg.caddy.enable [ "caddy.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "infinity";
        ExecStart = "${lib.getExe pkgs.deno} run --allow-read --allow-net ${configureScript} /run/stalwart-setup/desired-state.json";
      };
    };

    # ── oauth2-proxy (OIDC authentication gate for admin) ────────────────

    services.oauth2-proxy = {
      enable = true;
      provider = "oidc";
      redirectURL = "https://${cfg.domain}/oauth2/callback";
      httpAddress = "127.0.0.1:4180";
      email.domains = [ "*" ];
      keyFile = authEnvFile;
      extraConfig = {
        oidc-issuer-url = "https://${cfg.ssoDomain}";
        oidc-groups-claim = "urn:zitadel:iam:org:project:roles";
        prompt = "select_account";
        scope = "openid email profile urn:zitadel:iam:org:project:roles";
        skip-provider-button = "true";
        reverse-proxy = "true";
        upstream = "static://200";
        code-challenge-method = "S256";
        set-xauthrequest = "true";
      };
    };

    systemd.services.stalwart-auth-config = {
      description = "Assemble oauth2-proxy env file from OIDC credentials";
      requires = [
        zitadelCfg.configureService
        config.foundrix.services.secrets.oauth2-proxy-cookie-secret.service
      ];
      after = [
        zitadelCfg.configureService
        config.foundrix.services.secrets.oauth2-proxy-cookie-secret.service
      ];
      before = [ "oauth2-proxy.service" ];
      requiredBy = [ "oauth2-proxy.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = "stalwart-auth";
        RuntimeDirectoryMode = "0700";
        LoadCredential = [
          "cookie-secret:${cookieSecretPath}"
        ];

        ExecStart = pkgs.writeScript "stalwart-auth-config" ''
          #!${lib.getExe python3}
          import base64, os
          from pathlib import Path

          creds = dict(
              line.split("=", 1)
              for line in Path("${oauth2ProxyCredsPath}").read_text().strip().split("\n")
              if "=" in line
          )
          client_id = creds["CLIENT_ID"]
          client_secret = creds["CLIENT_SECRET"]

          cred_dir = os.environ["CREDENTIALS_DIRECTORY"]
          cookie_raw = Path(f"{cred_dir}/cookie-secret").read_bytes()
          cookie_b64 = base64.urlsafe_b64encode(cookie_raw).decode()

          env_path = Path("${authEnvFile}")
          env_path.write_text(
              f"OAUTH2_PROXY_CLIENT_ID={client_id}\n"
              f"OAUTH2_PROXY_CLIENT_SECRET={client_secret}\n"
              f"OAUTH2_PROXY_COOKIE_SECRET={cookie_b64}\n"
          )
          env_path.chmod(0o600)
          print(f"Wrote oauth2-proxy env file to {env_path}")
        '';
      };
    };

    systemd.services.oauth2-proxy = {
      requires = [
        "stalwart-auth-config.service"
        "caddy.service"
      ];
      after = [
        "stalwart-auth-config.service"
        "caddy.service"
      ];
      serviceConfig = {
        RestartSec = "5s";
        StartLimitIntervalSec = 300;
        StartLimitBurst = 30;
      };
    };

    # ── Self-service Caddy env ───────────────────────────────────────────

    systemd.services.stalwart-caddy-env = lib.mkIf (cfg.caddy.enable && cfg.selfService.enable) {
      description = "Generate self-service OIDC config for Caddy";
      requires = [ zitadelCfg.configureService ];
      after = [ zitadelCfg.configureService ];
      before = [ "caddy.service" ];
      requiredBy = [ "caddy.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "stalwart-caddy-env" ''
          client_id=$(cat "${selfServiceClientIdPath}")
          echo "MAIL_SELF_SERVICE_CLIENT_ID=$client_id" > /run/stalwart-caddy.env
          chmod 600 /run/stalwart-caddy.env
        '';
      };
    };

    systemd.services.caddy.serviceConfig.EnvironmentFile =
      lib.mkIf (cfg.caddy.enable && cfg.selfService.enable)
        (lib.mkAfter [ "/run/stalwart-caddy.env" ]);

    # ── Caddy virtual hosts ──────────────────────────────────────────────

    services.caddy.virtualHosts = lib.mkIf cfg.caddy.enable (
      let
        corsOrigins =
          [ "https://${cfg.domain}" ]
          ++ lib.optional (cfg.webmailDomain != null) "https://${cfg.webmailDomain}";
        corsOriginList = builtins.concatStringsSep ", " (map (o: ''"${o}"'') corsOrigins);
        adminRolePattern = ''\b${cfg.zitadel.adminRoleKey}\b'';
      in
      {
        # Main mail domain — admin UI, JMAP, oauth2-proxy, self-service
        ${cfg.domain} = {
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

            handle /oauth2/* {
              reverse_proxy 127.0.0.1:4180
            }

            ${lib.optionalString (cfg.webmailDomain != null) ''
            handle /.well-known/webfinger {
              route {
                header Access-Control-Allow-Origin "https://${cfg.webmailDomain}"
                header Vary Origin
                header Access-Control-Allow-Methods "GET, OPTIONS"
                header Access-Control-Allow-Headers "Accept, Content-Type"
                header Access-Control-Max-Age 86400
                header Content-Type "application/jrd+json"
                @options method OPTIONS
                respond @options 204
                respond `{"subject":"https://${cfg.domain}","links":[{"rel":"http://openid.net/specs/connect/1.0/issuer","href":"https://${cfg.ssoDomain}"}]}`
              }
            }
            ''}

            @api path /.well-known/* /auth/* /authorize/* /jmap/* /jmap /mail/* /autodiscover/*
            handle @api {
              @allowed_origin expression {http.request.header.Origin} in [${corsOriginList}]
              header @allowed_origin Access-Control-Allow-Origin {http.request.header.Origin}
              header @allowed_origin Vary Origin
              header @allowed_origin Access-Control-Allow-Methods "GET, POST, OPTIONS"
              header @allowed_origin Access-Control-Allow-Headers "Authorization, Content-Type"
              header @allowed_origin Access-Control-Max-Age 86400
              @options method OPTIONS
              respond @options 204
              reverse_proxy 127.0.0.1:${toString cfg.httpPort}
            }

            handle {
              forward_auth 127.0.0.1:4180 {
                uri /oauth2/auth
                copy_headers X-Auth-Request-User X-Auth-Request-Groups
                @error status 401
                handle_response @error {
                  redir * /oauth2/sign_in?rd={scheme}://{host}{uri}
                }
              }

              ${lib.optionalString cfg.selfService.enable ''
              handle /self-service-config.json {
                header Content-Type "application/json"
                respond `{"clientId":"{$MAIL_SELF_SERVICE_CLIENT_ID}","issuer":"https://${cfg.ssoDomain}"}`
              }
              ''}

              handle /api/* {
                reverse_proxy 127.0.0.1:${toString cfg.httpPort}
              }

              ${lib.optionalString cfg.selfService.enable ''
              handle_path /self-service* {
                header Content-Security-Policy "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self' https:; form-action 'none'; frame-ancestors 'none'; base-uri 'none'"
                root * ${selfServiceDir}
                try_files {path} /index.html
                file_server
              }
              ''}

              @admin header_regexp X-Auth-Request-Groups ${adminRolePattern}
              handle @admin {
                reverse_proxy 127.0.0.1:${toString cfg.httpPort}
              }

              ${lib.optionalString cfg.selfService.enable ''
              handle {
                header Content-Security-Policy "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self' https:; form-action 'none'; frame-ancestors 'none'; base-uri 'none'"
                root * ${selfServiceDir}
                try_files {path} /index.html
                file_server
              }
              ''}
            }
          '';
        };

        # ACME http-01 challenge handler + HTTPS redirect
        "http://${cfg.domain}" = lib.mkIf cfg.acme.enable {
          extraConfig = ''
            handle /.well-known/acme-challenge/* {
              reverse_proxy localhost:${toString cfg.httpPort}
            }
            handle {
              redir https://{host}{uri} permanent
            }
          '';
        };

        # MTA-STS policy
        "mta-sts.${cfg.orgDomain}".extraConfig = ''
          handle /.well-known/mta-sts.txt {
            header Content-Type "text/plain"
            respond "version: STSv1
          mode: enforce
          mx: ${cfg.domain}
          max_age: 604800
          "
          }
          handle {
            respond "Not Found" 404
          }
        '';

        # Thunderbird autoconfig
        "autoconfig.${cfg.orgDomain}".extraConfig = ''
          ${cfg.caddy.extraTlsConfig}
          reverse_proxy 127.0.0.1:${toString cfg.httpPort}
        '';

        # Outlook autodiscover
        "autodiscover.${cfg.orgDomain}".extraConfig = ''
          ${cfg.caddy.extraTlsConfig}
          reverse_proxy 127.0.0.1:${toString cfg.httpPort}
        '';
      }
    );

    # ── Firewall ─────────────────────────────────────────────────────────

    networking.firewall.allowedTCPPorts = [
      25
      465
      587
      993
    ];
  };
}
