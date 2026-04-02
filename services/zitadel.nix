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

  patPath = "/var/lib/zitadel/admin.pat";

  roleType = lib.types.submodule {
    options.displayName = lib.mkOption {
      type = lib.types.str;
      description = "Human-readable display name for this role";
    };
  };

  appType = lib.types.submodule (
    { name, config, ... }:
    {
      options = {
        type = lib.mkOption {
          type = lib.types.enum [
            "confidential"
            "public"
          ];
          description = ''
            OIDC app type.
            `confidential` apps have a client secret (server-side, e.g. oauth2-proxy).
            `public` apps use PKCE only (browser-based, e.g. SPAs).
          '';
        };

        redirectUris = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = "OAuth2 redirect URIs";
        };

        postLogoutRedirectUris = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Post-logout redirect URIs (primarily for public apps)";
        };

        outputPath = lib.mkOption {
          type = lib.types.str;
          default =
            if config.type == "confidential" then
              "/run/zitadel/${name}-creds.env"
            else
              "/run/zitadel/${name}-client-id";
          defaultText = ''
            Confidential: /run/zitadel/<name>-creds.env
            Public: /run/zitadel/<name>-client-id
          '';
          description = ''
            Path where the configure script writes credentials.
            Confidential apps get an env file with CLIENT_ID and CLIENT_SECRET.
            Public apps get a file containing just the client ID.
          '';
        };
      };
    }
  );

  projectType = lib.types.submodule {
    options = {
      apps = lib.mkOption {
        type = lib.types.attrsOf appType;
        default = { };
        description = "OIDC applications to create within this project";
      };

      roles = lib.mkOption {
        type = lib.types.attrsOf roleType;
        default = { };
        description = "Project roles to create";
      };

      userGrants = lib.mkOption {
        type = lib.types.attrsOf (lib.types.listOf lib.types.str);
        default = { };
        description = "Map of username → list of role keys to grant";
        example = {
          admin = [
            "mail-admin"
          ];
        };
      };
    };
  };

  dbPasswordSecret = config.foundrix.services.secrets."postgres-${cfg.database.name}-user-password";

  privacyPolicyConfigJson = pkgs.writeText "privacy-policy-config.json" (builtins.toJSON {
    organization = {
      name = cfg.privacyPolicy.organizationName;
      address = cfg.privacyPolicy.address;
    };
    contact = {
      email = cfg.privacyPolicy.contactEmail;
    };
    data = {
      location = cfg.privacyPolicy.dataLocation;
    };
    hosting_provider = {
      name = cfg.privacyPolicy.hostingProvider.name;
      location = cfg.privacyPolicy.hostingProvider.location;
      purpose = cfg.privacyPolicy.hostingProvider.purpose;
    };
    supervisory_authority = {
      name = cfg.privacyPolicy.supervisoryAuthority.name;
      address = cfg.privacyPolicy.supervisoryAuthority.address;
      website = cfg.privacyPolicy.supervisoryAuthority.website;
    };
    document = {
      last_updated = cfg.privacyPolicy.lastUpdated;
    };
  });

  privacyPolicyRendered = pkgs.runCommand "privacy-policy.html" {
    nativeBuildInputs = [ pkgs.gomplate pkgs.pandoc ];
  } ''
    gomplate -d config=${privacyPolicyConfigJson} -f ${./zitadel-privacy-policy.md} -o rendered.md
    pandoc rendered.md -f markdown -t html --standalone \
      --metadata title="Privacy Policy - ${cfg.privacyPolicy.organizationName}" \
      -o $out
  '';

  desiredState = builtins.toJSON {
    apiUrl = "http://${cfg.domain}:${toString cfg.port}";
    inherit patPath;
    org.primaryDomain = cfg.orgDomain;
    privacyPolicyLink =
      if cfg.privacyPolicy.enable then cfg.privacyPolicy.link
      else null;
    policies = {
      domainPolicy = {
        inherit (cfg.policies.domainPolicy) userLoginMustBeDomain validateOrgDomains;
      };
      loginPolicy = {
        inherit (cfg.policies.loginPolicy) allowRegister;
      };
    };
    projects = lib.mapAttrs (
      _: project: {
        apps = lib.mapAttrs (_: app: {
          inherit (app) type redirectUris postLogoutRedirectUris outputPath;
        }) project.apps;
        roles = lib.mapAttrs (_: role: {
          inherit (role) displayName;
        }) project.roles;
        inherit (project) userGrants;
      }
    ) cfg.projects;
  };

  configureScript = ./zitadel-configure.ts;
in
{
  imports = [
    foundrixModules.services.database
    foundrixModules.services.secrets
  ];

  options = namespaced __curPos {
    enable = lib.mkEnableOption "Zitadel identity provider with automated first-time setup";

    domain = lib.mkOption {
      type = lib.types.str;
      description = "External SSO domain (e.g. sso.example.com)";
      example = "sso.example.com";
    };

    orgDomain = lib.mkOption {
      type = lib.types.str;
      description = "Primary organization domain for login names (e.g. example.com)";
      example = "example.com";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Internal HTTP port Zitadel listens on";
    };

    externalPort = lib.mkOption {
      type = lib.types.port;
      default = 443;
      description = "External-facing port (typically 443 behind a reverse proxy)";
    };

    externalSecure = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether the external endpoint uses TLS";
    };

    instanceName = lib.mkOption {
      type = lib.types.str;
      description = "Zitadel instance display name";
      example = "My Organization";
    };

    orgName = lib.mkOption {
      type = lib.types.str;
      default = cfg.instanceName;
      defaultText = "Same as instanceName";
      description = "Default organization name";
    };

    admin = {
      username = lib.mkOption {
        type = lib.types.str;
        default = "admin";
        description = "Admin user login name";
      };

      firstName = lib.mkOption {
        type = lib.types.str;
        default = "Admin";
        description = "Admin user first name";
      };

      lastName = lib.mkOption {
        type = lib.types.str;
        default = cfg.instanceName;
        defaultText = "Same as instanceName";
        description = "Admin user last name";
      };

      email = lib.mkOption {
        type = lib.types.str;
        default = "${cfg.admin.username}@${cfg.orgDomain}";
        defaultText = "<username>@<orgDomain>";
        description = "Admin user email address";
      };
    };

    machineUser = {
      username = lib.mkOption {
        type = lib.types.str;
        default = "nix-configurator";
        description = "Machine user for the setup PAT";
      };

      displayName = lib.mkOption {
        type = lib.types.str;
        default = "NixOS Configurator";
        description = "Machine user display name";
      };
    };

    policies = {
      domainPolicy = {
        userLoginMustBeDomain = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Require login names to include the org domain";
        };
        validateOrgDomains = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Require DNS validation of org domains";
        };
      };
      loginPolicy = {
        allowRegister = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Allow self-registration of new users";
        };
      };
    };

    projects = lib.mkOption {
      type = lib.types.attrsOf projectType;
      default = { };
      description = "Zitadel projects with OIDC apps, roles, and user grants";
    };

    database = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "zitadel";
        description = "PostgreSQL database name";
      };
    };

    caddy = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Configure a Caddy virtual host for the SSO domain";
      };

      extraConfig = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Extra Caddyfile directives prepended to the virtual host (e.g. custom TLS block)";
      };
    };

    privacyPolicy = {
      enable = lib.mkEnableOption "serving a privacy policy page and setting its link in Zitadel";

      organizationName = lib.mkOption {
        type = lib.types.str;
        default = cfg.instanceName;
        defaultText = "Same as instanceName";
        description = "Data controller organization name";
      };

      contactEmail = lib.mkOption {
        type = lib.types.str;
        default = "privacy@${cfg.orgDomain}";
        defaultText = "privacy@<orgDomain>";
        description = "Privacy-related contact email address";
      };

      address = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Postal address of the data controller";
      };

      dataLocation = lib.mkOption {
        type = lib.types.str;
        default = "the European Union";
        description = "Geographic region where data is stored";
      };

      hostingProvider = {
        name = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Hosting provider name (leave empty to omit from policy)";
        };
        location = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Hosting provider server location";
        };
        purpose = lib.mkOption {
          type = lib.types.str;
          default = "Server hosting";
          description = "Purpose of the hosting provider relationship";
        };
      };

      supervisoryAuthority = {
        name = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Data protection supervisory authority name (leave empty to omit)";
        };
        address = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Supervisory authority address";
        };
        website = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Supervisory authority website";
        };
      };

      lastUpdated = lib.mkOption {
        type = lib.types.str;
        description = "Date string shown on the privacy policy (e.g. '2 April 2026')";
      };

      content = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        description = ''
          Override the rendered privacy policy HTML.
          When set, the gomplate template is bypassed entirely.
          Must be a derivation producing a single HTML file.
        '';
      };

      link = lib.mkOption {
        type = lib.types.str;
        default = "https://${cfg.domain}/privacy-policy";
        defaultText = "https://<domain>/privacy-policy";
        description = "URL set as Zitadel's 'Link to Privacy Policy'";
      };
    };

    configureService = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "zitadel-configure.service";
      description = "Systemd unit that completes once Zitadel is fully configured";
    };

    readyService = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "zitadel-ready.service";
      description = "Systemd unit that completes once Zitadel's health check passes";
    };

    patPath = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = patPath;
      description = "Path to the machine user's personal access token";
    };
  };

  config = lib.mkIf cfg.enable {
    foundrix.services.database.databases.${cfg.database.name} = {
      user = cfg.database.name;
      adminPrivileges = true;
    };

    foundrix.services.secrets = {
      zitadel-master-key = {
        persistent = true;
        length = 32;
        binary = true;
      };
      zitadel-admin-password = {
        persistent = true;
        length = 24;
        symbols = true;
      };
    };

    services.zitadel = {
      enable = true;
      tlsMode = "external";
      masterKeyFile = "/run/credentials/zitadel.service/master-key";
      settings = {
        Port = cfg.port;
        ExternalDomain = cfg.domain;
        ExternalPort = cfg.externalPort;
        ExternalSecure = cfg.externalSecure;
        Machine.Identification.Hostname.Enabled = true;
        Machine.Identification.Webhook.Enabled = false;
        ServicePing.Enabled = false;
        DefaultInstance.DomainPolicy.ValidateOrgDomains = cfg.policies.domainPolicy.validateOrgDomains;
        DefaultInstance.DomainPolicy.UserLoginMustBeDomain = cfg.policies.domainPolicy.userLoginMustBeDomain;
        DefaultInstance.LoginPolicy.AllowRegister = cfg.policies.loginPolicy.allowRegister;
        Database.postgres = {
          Host = "/run/postgresql";
          Port = 5432;
          Database = cfg.database.name;
          User.Username = cfg.database.name;
          User.SSL.Mode = "disable";
          Admin.Username = cfg.database.name;
          Admin.SSL.Mode = "disable";
          MaxOpenConns = 25;
          MaxIdleConns = 10;
          MaxConnLifetime = "1h";
          MaxConnIdleTime = "5m";
        };
      };
      extraSettingsPaths = [ "/run/zitadel/db-config.yaml" ];
      steps.FirstInstance = {
        InstanceName = cfg.instanceName;
        PatPath = patPath;
        Org = {
          Name = cfg.orgName;
          Human = {
            UserName = cfg.admin.username;
            FirstName = cfg.admin.firstName;
            LastName = cfg.admin.lastName;
            Email.Address = cfg.admin.email;
            Email.Verified = true;
          };
          Machine = {
            Machine = {
              Username = cfg.machineUser.username;
              Name = cfg.machineUser.displayName;
            };
            Pat.ExpirationDate = "2099-01-01T00:00:00Z";
          };
        };
      };
      extraStepsPaths = [ "/run/zitadel/admin-password.yaml" ];
    };

    systemd.services.zitadel-db-config = {
      description = "Generate Zitadel runtime config from ephemeral secrets";
      requires =
        config.foundrix.services.database.prerequisiteUnits
        ++ [ config.foundrix.services.secrets.zitadel-admin-password.service ];
      after =
        config.foundrix.services.database.prerequisiteUnits
        ++ [ config.foundrix.services.secrets.zitadel-admin-password.service ];
      before = [ "zitadel.service" ];
      requiredBy = [ "zitadel.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = "zitadel";
        RuntimeDirectoryMode = "0750";
        User = "zitadel";
        LoadCredential = [
          "admin-password:${config.foundrix.services.secrets.zitadel-admin-password.path}"
        ];

        ExecStart = pkgs.writeScript "generate-zitadel-runtime-config" ''
          #!${lib.getExe python3}
          import json, os
          from pathlib import Path

          db_password = Path("${dbPasswordSecret.path}").read_text()
          Path("/run/zitadel/db-config.yaml").write_text(json.dumps({
              "Database": {"postgres": {
                  "User": {"Password": db_password},
                  "Admin": {"Password": db_password},
              }}
          }))

          Path("/run/zitadel/desired-state.json").write_text(${builtins.toJSON desiredState})

          cred_dir = os.environ.get("CREDENTIALS_DIRECTORY", "")
          admin_password = Path(f"{cred_dir}/admin-password").read_text()
          Path("/run/zitadel/admin-password.yaml").write_text(json.dumps({
              "FirstInstance": {"Org": {"Human": {"Password": admin_password}}}
          }))
          print(f"Admin password: {admin_password}")
        '';
      };
    };

    systemd.services.zitadel-ready = {
      description = "Wait for Zitadel to be ready";
      requires = [ "zitadel.service" ];
      after = [ "zitadel.service" ];
      requiredBy = [ "zitadel-configure.service" ];
      before = [ "zitadel-configure.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "infinity";

        ExecStart = pkgs.writeScript "zitadel-ready" ''
          #!${lib.getExe python3}
          import time, urllib.request, sys

          url = "http://localhost:${toString cfg.port}/debug/healthz"
          while True:
              try:
                  with urllib.request.urlopen(url, timeout=2) as resp:
                      if resp.status == 200:
                          print("Zitadel is ready")
                          sys.exit(0)
              except Exception:
                  pass
              time.sleep(1)
        '';
      };
    };

    systemd.services.zitadel-configure = {
      description = "Apply declarative Zitadel configuration";
      requires = [ "zitadel-ready.service" ];
      after = [ "zitadel-ready.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "infinity";
        ExecStart = "${lib.getExe pkgs.deno} run --allow-read --allow-net --allow-write=/run/zitadel ${configureScript} /run/zitadel/desired-state.json";
      };
    };

    systemd.services.zitadel = {
      requires =
        config.foundrix.services.database.prerequisiteUnits
        ++ [
          "zitadel-db-config.service"
          config.foundrix.services.secrets.zitadel-master-key.service
        ];
      after =
        config.foundrix.services.database.prerequisiteUnits
        ++ [
          "zitadel-db-config.service"
          config.foundrix.services.secrets.zitadel-master-key.service
        ];
      serviceConfig = {
        BindReadOnlyPaths = [ "/run/postgresql" ];
        StateDirectory = "zitadel";
        LoadCredential = [
          "master-key:${config.foundrix.services.secrets.zitadel-master-key.path}"
        ];
      };
    };

    systemd.services.caddy = lib.mkIf cfg.caddy.enable {
      requires = [ cfg.configureService ];
      after = [ cfg.configureService ];
    };

    services.caddy.virtualHosts.${cfg.domain} = lib.mkIf cfg.caddy.enable {
      logFormat = lib.mkForce ''
        level INFO
        output stdout
        format json
      '';
      extraConfig = ''
        ${cfg.caddy.extraConfig}
        header {
          defer
          -Server
          -Via
        }

        header {
          Strict-Transport-Security "max-age=31536000"
          X-Content-Type-Options nosniff
        }

        ${lib.optionalString cfg.privacyPolicy.enable ''
        handle /privacy-policy {
          header Content-Type "text/html; charset=utf-8"
          respond `${builtins.readFile (
            if cfg.privacyPolicy.content != null then cfg.privacyPolicy.content
            else privacyPolicyRendered
          )}`
        }
        ''}

        reverse_proxy localhost:${toString cfg.port}
      '';
    };
  };
}
