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

  nullableOption =
    type: default: description:
    lib.mkOption {
      type = lib.types.nullOr type;
      inherit default description;
    };

  passwordComplexityType = lib.types.submodule {
    options = {
      minLength = lib.mkOption {
        type = lib.types.int;
        default = 8;
        description = "Minimum password length";
      };
      hasNumber = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Require at least one digit";
      };
      hasSymbol = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Require at least one symbol";
      };
      hasLowercase = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Require at least one lowercase letter";
      };
      hasUppercase = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Require at least one uppercase letter";
      };
    };
  };

  brandingType = lib.types.submodule {
    options = {
      themeMode = lib.mkOption {
        type = lib.types.enum [
          "auto"
          "light"
          "dark"
        ];
        default = "auto";
        description = "Theme mode restriction (auto = user chooses)";
      };
      primaryColor = lib.mkOption {
        type = lib.types.str;
        default = "#2073c4";
        description = "Primary color (hex)";
      };
      backgroundColor = lib.mkOption {
        type = lib.types.str;
        default = "#fafafa";
        description = "Background color for light mode (hex)";
      };
      warnColor = lib.mkOption {
        type = lib.types.str;
        default = "#cd3d56";
        description = "Warning color for light mode (hex)";
      };
      fontColor = lib.mkOption {
        type = lib.types.str;
        default = "#000000";
        description = "Font color for light mode (hex)";
      };
      primaryColorDark = lib.mkOption {
        type = lib.types.str;
        default = "#2073c4";
        description = "Primary color for dark mode (hex)";
      };
      backgroundColorDark = lib.mkOption {
        type = lib.types.str;
        default = "#111827";
        description = "Background color for dark mode (hex)";
      };
      warnColorDark = lib.mkOption {
        type = lib.types.str;
        default = "#ff3b5b";
        description = "Warning color for dark mode (hex)";
      };
      fontColorDark = lib.mkOption {
        type = lib.types.str;
        default = "#ffffff";
        description = "Font color for dark mode (hex)";
      };
      hideLoginNameSuffix = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Hide the org domain suffix on the login form";
      };
      disableWatermark = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Disable the ZITADEL watermark on the login page";
      };
      logoUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Logo image for light mode (path to image file)";
      };
      logoUrlDark = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Logo image for dark mode (path to image file)";
      };
      iconUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Icon image for light mode (path to image file)";
      };
      iconUrlDark = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Icon image for dark mode (path to image file)";
      };
      fontUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Custom font file for the login interface (TTF, OTF, WOFF, WOFF2)";
      };
    };
  };

  themeModeToInt =
    mode:
    {
      auto = 1;
      light = 3;
      dark = 2;
    }
    .${mode};

  secretGeneratorType = lib.types.submodule {
    options = {
      expirationMinutes = lib.mkOption {
        type = lib.types.int;
        description = "Expiration time in minutes";
      };
      length = lib.mkOption {
        type = lib.types.int;
        description = "Length of the generated secret";
      };
      includeDigits = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Include digits (0-9)";
      };
      includeSymbols = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Include symbols";
      };
      includeLowerLetters = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Include lowercase letters";
      };
      includeUpperLetters = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Include uppercase letters";
      };
    };
  };

  orgSettingsType = lib.types.submodule {
    options = {
      passwordComplexity =
        nullableOption passwordComplexityType null
          "Password complexity policy for this organization. Null inherits the Zitadel default.";
      branding =
        nullableOption brandingType null
          "Login UI branding for this organization. Null inherits the Zitadel default.";
    };
  };

  serializePasswordComplexity = pc: {
    inherit (pc)
      minLength
      hasUppercase
      hasLowercase
      hasNumber
      hasSymbol
      ;
  };

  serializeBranding = b: {
    inherit (b)
      primaryColor
      backgroundColor
      warnColor
      fontColor
      primaryColorDark
      backgroundColorDark
      warnColorDark
      fontColorDark
      hideLoginNameSuffix
      disableWatermark
      ;
    themeMode = themeModeToInt b.themeMode;
    logoUrl = if b.logoUrl != null then toString b.logoUrl else null;
    logoUrlDark = if b.logoUrlDark != null then toString b.logoUrlDark else null;
    iconUrl = if b.iconUrl != null then toString b.iconUrl else null;
    iconUrlDark = if b.iconUrlDark != null then toString b.iconUrlDark else null;
    fontUrl = if b.fontUrl != null then toString b.fontUrl else null;
  };

  serializeSecretGenerator = sg: {
    inherit (sg)
      length
      includeDigits
      includeSymbols
      includeLowerLetters
      includeUpperLetters
      ;
    expirySeconds = sg.expirationMinutes * 60;
  };

  roleType = lib.types.submodule {
    options.displayName = lib.mkOption {
      type = lib.types.str;
      description = "Human-readable display name for this role";
    };
  };

  actionType = lib.types.submodule {
    options = {
      script = lib.mkOption {
        type = lib.types.str;
        description = ''
          JavaScript function body for the Zitadel Action (v1).
          The function name must match the action's attribute name.
        '';
      };

      triggers = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              flowType = lib.mkOption {
                type = lib.types.enum [
                  "complementToken"
                  "externalAuthentication"
                  "internalAuthentication"
                  "complementSAMLResponse"
                ];
                description = "The flow type this action is triggered on";
              };
              triggerType = lib.mkOption {
                type = lib.types.enum [
                  "postAuthentication"
                  "preCreation"
                  "postCreation"
                  "preUserinfoCreation"
                  "preAccessTokenCreation"
                  "preSAMLResponseCreation"
                ];
                description = "The specific trigger within the flow";
              };
            };
          }
        );
        description = "Flow/trigger combinations this action should be wired to";
      };

      timeout = lib.mkOption {
        type = lib.types.str;
        default = "10s";
        description = "Maximum execution time for this action";
      };

      allowedToFail = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether action failure should be non-fatal";
      };
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

        accessTokenType = lib.mkOption {
          type = lib.types.enum [
            "bearer"
            "jwt"
          ];
          default = "bearer";
          description = ''
            Access token format issued by Zitadel for this app.
            `bearer` issues opaque tokens (default).
            `jwt` issues signed JWT access tokens.
          '';
        };

        grantTypes = lib.mkOption {
          type = lib.types.nonEmptyListOf (
            lib.types.enum [
              "authorization-code"
              "implicit"
              "refresh-token"
              "device-code"
              "token-exchange"
            ]
          );
          default = [ "authorization-code" ];
          description = ''
            OAuth2 grant types this app may use. Zitadel rejects any grant the
            app does not list with `unauthorized_client`, and the configure
            script rewrites this on every run — so a grant enabled by hand in
            the console is reverted on the next deploy and belongs here
            instead.

            `token-exchange` additionally requires the instance to permit
            impersonation; the grant alone is not enough.
          '';
          example = [
            "authorization-code"
            "token-exchange"
          ];
        };

        outputPath = lib.mkOption {
          type = lib.types.str;
          default =
            if config.type == "confidential" then
              "/var/credentials/zitadel-${name}-creds.env"
            else
              "/run/zitadel/${name}-client-id";
          defaultText = ''
            Confidential: /var/credentials/zitadel-<name>-creds.env
            Public: /run/zitadel/<name>-client-id
          '';
          description = ''
            Path where the configure script writes credentials.
            Confidential apps get an env file with CLIENT_ID and CLIENT_SECRET.
            Public apps get a file containing just the client ID.

            Confidential apps default to a PERSISTENT path: Zitadel cannot
            read a client secret back, so converge reuses the stored one to
            stay idempotent. On a tmpfs path every reboot would lose it and
            force a regeneration, invalidating every consumer's copy.
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

  # Served from disk rather than inlined into the Caddyfile with `respond`.
  # Any brace in the document — a CSS rule in a <style> block is enough — is
  # read by the Caddyfile parser as the start of a block and aborts the config
  # with "Unexpected next token after '{' on same line", taking the whole web
  # server down with it. Backticks do not protect against this. Serving the
  # file also drops an import-from-derivation: the old form had to build the
  # document during evaluation just to read it back as a string.
  #
  # `root` needs a directory, and `content` is a single file whose parent is
  # the store root, so it gets a directory of its own here.
  privacyPolicyDir = pkgs.runCommand "zitadel-privacy-policy" { } ''
    mkdir -p $out
    cp ${cfg.privacyPolicy.content} $out/privacy-policy.html
  '';

  userPasswordServices = lib.mapAttrsToList (
    username: _: config.foundrix.services.secrets."zitadel-user-${username}-password".service
  ) cfg.users;

  desiredState = builtins.toJSON {
    apiUrl = "http://${cfg.webDomain}:${toString cfg.port}";
    inherit patPath;
    adminOrg = cfg.adminOrg;
    adminUsername = cfg.admin.username;
    orgDomains = builtins.attrNames cfg.orgDomains;
    users = lib.mapAttrsToList (username: user: {
      inherit username;
      inherit (user) displayName;
      passwordPath = config.foundrix.services.secrets."zitadel-user-${username}-password".path;
    }) cfg.users;
    privacyPolicyLink = if cfg.privacyPolicy.enable then cfg.privacyPolicy.link else null;
    instance = {
      passwordComplexity =
        if cfg.instance.passwordComplexity != null then
          serializePasswordComplexity cfg.instance.passwordComplexity
        else
          null;
      branding = if cfg.instance.branding != null then serializeBranding cfg.instance.branding else null;
      languages =
        let
          l = cfg.instance.languages;
        in
        if l.default != null || l.allowed != null then
          {
            inherit (l) default allowed;
          }
        else
          null;
      oidcSettings =
        if cfg.instance.oidcSettings != null then
          let
            o = cfg.instance.oidcSettings;
          in
          {
            accessTokenLifetimeSeconds = o.accessTokenLifetimeHours * 3600;
            idTokenLifetimeSeconds = o.idTokenLifetimeHours * 3600;
            refreshTokenExpirationSeconds = o.refreshTokenLifetimeDays * 86400;
            refreshTokenIdleExpirationSeconds = o.refreshTokenIdleLifetimeDays * 86400;
          }
        else
          null;
      secretGenerators =
        if cfg.instance.secretGenerators != null then
          lib.mapAttrs (_: serializeSecretGenerator) cfg.instance.secretGenerators
        else
          null;
    };
    orgs =
      let
        mapped = lib.mapAttrs (_: org: {
          passwordComplexity =
            if org.passwordComplexity != null then serializePasswordComplexity org.passwordComplexity else null;
          branding = if org.branding != null then serializeBranding org.branding else null;
        }) cfg.orgDomains;
      in
      if mapped == { } then null else mapped;
    policies = {
      domainPolicy = {
        inherit (cfg.policies.domainPolicy) userLoginMustBeDomain validateOrgDomains;
      };
      loginPolicy = {
        inherit (cfg.policies.loginPolicy) allowRegister allowExternalIdp;
      };
      inherit (cfg.policies) disallowPublicOrgRegistration enableImpersonation;
    };
    adminIamRoles = cfg.admin.iamRoles;
    projects = lib.mapAttrs (_: project: {
      apps = lib.mapAttrs (_: app: {
        inherit (app)
          type
          redirectUris
          postLogoutRedirectUris
          outputPath
          accessTokenType
          grantTypes
          ;
      }) project.apps;
      roles = lib.mapAttrs (_: role: {
        inherit (role) displayName;
      }) project.roles;
      inherit (project) userGrants;
    }) cfg.projects;
    actions = lib.mapAttrs (_: action: {
      inherit (action)
        script
        triggers
        timeout
        allowedToFail
        ;
    }) cfg.actions;
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

    webDomain = lib.mkOption {
      type = lib.types.str;
      description = "External SSO/web domain (e.g. sso.example.com)";
      example = "sso.example.com";
    };

    adminOrg = lib.mkOption {
      type = lib.types.str;
      description = "Organization domain that serves as the bootstrap/admin org. Must be a key in orgDomains.";
      example = "example.com";
    };

    orgDomains = lib.mkOption {
      type = lib.types.attrsOf orgSettingsType;
      default = { };
      description = "Organization domains and their settings. Each key is a domain (e.g. example.com). All domains are peers.";
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
      default = cfg.adminOrg;
      defaultText = "Same as adminOrg";
      description = ''
        Name of the bootstrap organization.

        Named after its domain, like every other org: the configure script
        creates additional orgs as `createOrg(domain)`, so defaulting this to
        the instance name would leave the first org labelled on a different
        principle from its siblings.

        Only read when the instance is first created — Zitadel's FirstInstance
        step runs against an empty database — so changing it renames nothing
        on an existing deployment.
      '';
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
        default = "${cfg.admin.username}@${cfg.adminOrg}";
        defaultText = "<username>@<adminOrg>";
        description = "Admin user email address";
      };

      iamRoles = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Instance-level manager roles to ensure on the admin user, beyond the
          IAM_OWNER it receives at first-instance setup.

          Additive only: the configure script unions these with whatever roles
          the account already holds. Zitadel's update call replaces the entire
          role list, so writing these alone would strip IAM_OWNER and lock the
          operator out of the console.
        '';
        example = [ "IAM_END_USER_IMPERSONATOR" ];
      };
    };

    users = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options.displayName = lib.mkOption {
              type = lib.types.str;
              default = name;
              defaultText = "the attribute name";
              description = "Display name shown for this user";
            };
          }
        )
      );
      default = { };
      description = ''
        Human users to create in the admin organization, keyed by login name.

        For accounts a deployment needs to exist in its own right rather than
        because a person asked for one — a catch-all sink, for instance.
        People get created by an operator, not declared here.

        Each gets a generated password under /var/credentials, since an
        account nobody can sign into is not much of an account. Created only
        if absent: an existing user of the same name is left alone, password
        included.
      '';
      example = {
        void = {
          displayName = "Catch-all";
        };
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
          default = builtins.length (builtins.attrNames cfg.orgDomains) > 1;
          defaultText = "true if more than one org is defined, false otherwise";
          description = "Add organization domain as suffix to login names. Useful with multiple orgs to ensure uniqueness.";
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
        allowExternalIdp = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Allow login with external identity providers";
        };
      };
      disallowPublicOrgRegistration = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Disallow public organization registration";
      };

      enableImpersonation = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Permit token exchange to issue a token for another user. Off by
          default: it lets a suitably privileged account act as any end user,
          so it should be turned on only where something concrete needs it.

          Necessary but not sufficient — the acting user also needs an
          `*_IMPERSONATOR` role (see {option}`admin.iamRoles`) and the client
          needs the `token-exchange` grant.
        '';
      };
    };

    instance = {
      passwordComplexity =
        nullableOption passwordComplexityType null
          "Instance-wide default password complexity policy. Null leaves the Zitadel default.";

      branding =
        nullableOption brandingType null
          "Instance-wide default login UI branding. Null leaves the Zitadel default.";

      languages = {
        default = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Default language code (e.g. 'en'). Null leaves the Zitadel default.";
          example = "en";
        };
        allowed = lib.mkOption {
          type = lib.types.nullOr (lib.types.listOf lib.types.str);
          default = null;
          description = "Restrict allowed languages. Null means all languages are allowed.";
          example = [
            "en"
            "de"
          ];
        };
      };

      oidcSettings = nullableOption (lib.types.submodule {
        options = {
          accessTokenLifetimeHours = lib.mkOption {
            type = lib.types.int;
            default = 12;
            description = "Access token maximum lifetime in hours";
          };
          idTokenLifetimeHours = lib.mkOption {
            type = lib.types.int;
            default = 12;
            description = "ID token maximum lifetime in hours";
          };
          refreshTokenLifetimeDays = lib.mkOption {
            type = lib.types.int;
            default = 90;
            description = "Refresh token maximum lifetime in days";
          };
          refreshTokenIdleLifetimeDays = lib.mkOption {
            type = lib.types.int;
            default = 30;
            description = "Idle refresh token maximum lifetime in days";
          };
        };
      }) null "Instance-wide OIDC token lifetime settings. Null leaves the Zitadel defaults.";

      secretGenerators =
        nullableOption (lib.types.attrsOf secretGeneratorType) null
          "Per-type secret/code generator settings (e.g. verification codes). Null leaves the Zitadel defaults.";
    };

    projects = lib.mkOption {
      type = lib.types.attrsOf projectType;
      default = { };
      description = "Zitadel projects with OIDC apps, roles, and user grants";
    };

    actions = lib.mkOption {
      type = lib.types.attrsOf actionType;
      default = { };
      description = ''
        Zitadel Actions (v1) — inline JavaScript snippets that run on
        specific flows/triggers (e.g., complement token to add custom claims).
        Attribute names become both the action name and the JS function name.
      '';
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

      content = lib.mkOption {
        type = lib.types.package;
        description = ''
          The privacy policy to serve: a derivation producing a single HTML
          file, supplied by the consumer.

          Deliberately not templated here. foundrix is infrastructure, and who
          the controller is, where they can be written to, and which authority
          is competent are facts about an operator, not about a service — a
          module that renders them ends up owning legal text it cannot keep
          correct for anyone. Consumers write their own document and pass it in.
        '';
      };

      link = lib.mkOption {
        type = lib.types.str;
        default = "https://${cfg.webDomain}/privacy-policy";
        defaultText = "https://<webDomain>/privacy-policy";
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
    }
    // lib.mapAttrs' (
      username: _:
      lib.nameValuePair "zitadel-user-${username}-password" {
        persistent = true;
        length = 24;
        symbols = true;
      }
    ) cfg.users;

    services.zitadel = {
      enable = true;
      tlsMode = "external";
      masterKeyFile = "/run/credentials/zitadel.service/master-key";
      settings = {
        Port = cfg.port;
        ExternalDomain = cfg.webDomain;
        ExternalPort = cfg.externalPort;
        ExternalSecure = cfg.externalSecure;
        Machine.Identification.Hostname.Enabled = true;
        Machine.Identification.Webhook.Enabled = false;
        ServicePing.Enabled = false;
        DefaultInstance.DomainPolicy.ValidateOrgDomains = cfg.policies.domainPolicy.validateOrgDomains;
        DefaultInstance.DomainPolicy.UserLoginMustBeDomain =
          cfg.policies.domainPolicy.userLoginMustBeDomain;
        DefaultInstance.LoginPolicy.AllowRegister = cfg.policies.loginPolicy.allowRegister;
        DefaultInstance.LoginPolicy.AllowExternalIdp = cfg.policies.loginPolicy.allowExternalIdp;
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
      requires = config.foundrix.services.database.prerequisiteUnits ++ [
        config.foundrix.services.secrets.zitadel-admin-password.service
      ];
      after = config.foundrix.services.database.prerequisiteUnits ++ [
        config.foundrix.services.secrets.zitadel-admin-password.service
      ];
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
      # Each declared user's password is generated before it can be set on the
      # account being created.
      requires = [ "zitadel-ready.service" ] ++ userPasswordServices;
      after = [ "zitadel-ready.service" ] ++ userPasswordServices;

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "infinity";
        ExecStart = "${lib.getExe pkgs.deno} run --allow-read --allow-net --allow-write=/run/zitadel,/var/credentials ${configureScript} /run/zitadel/desired-state.json";
      };
    };

    systemd.services.zitadel = {
      requires = config.foundrix.services.database.prerequisiteUnits ++ [
        "zitadel-db-config.service"
        config.foundrix.services.secrets.zitadel-master-key.service
      ];
      after = config.foundrix.services.database.prerequisiteUnits ++ [
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

    services.caddy.virtualHosts.${cfg.webDomain} = lib.mkIf cfg.caddy.enable {
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
            root * ${privacyPolicyDir}
            rewrite * /privacy-policy.html
            file_server
          }
        ''}

        reverse_proxy localhost:${toString cfg.port}
      '';
    };
  };
}
