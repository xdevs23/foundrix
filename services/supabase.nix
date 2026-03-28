# Supabase self-hosted module
#
# Provides a complete Supabase deployment via Docker Compose with:
# - All core Supabase services (PostgreSQL, Kong, GoTrue, PostgREST, Realtime, Storage, etc.)
# - Automatic secret generation (JWT keys, passwords, encryption keys)
# - Optional database migrations via supabase-cli
#
# Usage: set foundrix.services.supabase.supabaseSource to the upstream supabase repo path
# (typically a flake input with flake = false pointing at github:supabase/supabase)
{
  lib,
  pkgs,
  config,
  namespaced,
  namespacedCfg,
  foundrixPkgs,
  ...
}:
let
  cfg = namespacedCfg __curPos;
  images = foundrixPkgs.supabase-images;
  secretsPrefix = "/var/credentials/supabase";

  secretNames = [
    "postgres-password"
    "jwt-secret"
    "anon-key"
    "dashboard-password"
    "secret-key-base"
    "vault-enc-key"
    "pg-meta-crypto-key"
  ];

  secretServiceUnits = map (name: "generate-secret-supabase-${name}.service") secretNames ++ [
    "supabase-generate-service-role-key.service"
  ];

  # ── JWT generation ──────────────────────────────────────────────────

  generateJwt =
    role:
    pkgs.writeShellScript "generate-jwt-${role}" ''
      set -euo pipefail

      header=$(<${
        pkgs.writeText "" (
          builtins.toJSON {
            alg = "HS256";
            typ = "JWT";
          }
        )
      })
      now=$(date +%s)
      exp=$((now + 315360000))

      payload=$(${lib.getExe pkgs.jq} -cn \
        --arg role "${role}" \
        --argjson iat "$now" \
        --argjson exp "$exp" \
        '{"iss":"supabase","iat":$iat,"exp":$exp,"role":"${role}"}')

      b64url() { ${lib.getExe pkgs.openssl} base64 -A | tr '+/' '-_' | tr -d '='; }

      header_b64=$(echo -n "$header" | b64url)
      payload_b64=$(echo -n "$payload" | b64url)

      signature=$(echo -n "''${header_b64}.''${payload_b64}" | \
        ${lib.getExe pkgs.openssl} dgst -sha256 -hmac "$(< ${secretsPrefix}-jwt-secret)" -binary | b64url)

      echo -n "''${header_b64}.''${payload_b64}.''${signature}"
    '';

  generateServiceRoleKey = pkgs.writeShellScript "supabase-generate-service-role-key" ''
    set -euo pipefail
    ${generateJwt "service_role"} > "${secretsPrefix}-service-role-key"
    echo -n "SERVICE_ROLE_KEY=" > "${secretsPrefix}-service-role-key.variant"
    cat "${secretsPrefix}-service-role-key" >> "${secretsPrefix}-service-role-key.variant"
  '';

  # ── Secret definitions ──────────────────────────────────────────────

  secretProps = {
    postgres-password = {
      length = 32;
      prefix = "POSTGRES_PASSWORD=";
      requiredBy = [ "supabase-stack.service" ];
    };
    jwt-secret = {
      length = 64;
      prefix = "JWT_SECRET=";
    };
    anon-key = {
      prefix = "ANON_KEY=";
      requiredBy = [ "supabase-stack.service" ];
    };
    dashboard-password = {
      length = 24;
      prefix = "DASHBOARD_PASSWORD=";
      requiredBy = [ "supabase-stack.service" ];
    };
    secret-key-base = {
      length = 64;
      prefix = "SECRET_KEY_BASE=";
      requiredBy = [ "supabase-stack.service" ];
    };
    vault-enc-key = {
      length = 32;
      prefix = "VAULT_ENC_KEY=";
      requiredBy = [ "supabase-stack.service" ];
    };
    pg-meta-crypto-key = {
      length = 32;
      prefix = "PG_META_CRYPTO_KEY=";
      requiredBy = [ "supabase-stack.service" ];
    };
  };

  secretsConfig = lib.listToAttrs (
    map (
      name:
      lib.nameValuePair "supabase-${name}" (
        {
          owner = "root";
          group = "docker";
          mode = "0440";
        }
        // secretProps.${name}
      )
    ) secretNames
  );

  # ── Docker Compose helpers ──────────────────────────────────────────

  env = name: "\${${name}}";
  imageRef = img: img.destNameTag;

  pg = {
    host = cfg.postgres.host;
    port = toString cfg.postgres.port;
    db = cfg.postgres.database;
  };

  apiExternalUrl = "https://${cfg.domain}";
  dbUrl = user: "postgres://${user}:${env "POSTGRES_PASSWORD"}@${pg.host}:${pg.port}/${pg.db}";

  baseService = image: {
    image = imageRef image;
    pull_policy = "never";
    restart = "unless-stopped";
    extra_hosts = [ "host.docker.internal:host-gateway" ];
  };

  healthcheck =
    {
      test,
      timeout ? "5s",
      interval ? "5s",
      retries ? 3,
    }:
    {
      inherit
        test
        timeout
        interval
        retries
        ;
    };

  wgetHealth =
    url:
    healthcheck {
      test = [
        "CMD"
        "wget"
        "--no-verbose"
        "--tries=1"
        "--spider"
        url
      ];
    };

  curlHealth =
    url:
    healthcheck {
      test = [
        "CMD"
        "curl"
        "-sSfL"
        "--head"
        "-o"
        "/dev/null"
        url
      ];
    };

  # ── Docker Compose service definitions ──────────────────────────────

  supabaseInitScripts = "${cfg.supabaseSource}/docker/volumes/db";

  initScripts = {
    "realtime.sql" = "migrations/99-realtime.sql";
    "webhooks.sql" = "init-scripts/98-webhooks.sql";
    "roles.sql" = "init-scripts/99-roles.sql";
    "jwt.sql" = "init-scripts/99-jwt.sql";
    "_supabase.sql" = "migrations/97-_supabase.sql";
    "logs.sql" = "migrations/99-logs.sql";
    "pooler.sql" = "migrations/99-pooler.sql";
  };

  initVolumes = lib.mapAttrsToList (
    file: target: "${supabaseInitScripts}/${file}:/docker-entrypoint-initdb.d/${target}:ro"
  ) initScripts;

  dockerComposeConfig = {
    name = "supabase";

    services = {
      db = baseService images.postgres // {
        container_name = "supabase-db";
        ports = [ "127.0.0.1:${pg.port}:${pg.port}" ];
        volumes = [ "${cfg.stateDir}/db/data:/var/lib/postgresql/data" ] ++ initVolumes;
        healthcheck = healthcheck {
          test = [
            "CMD"
            "pg_isready"
            "-U"
            "postgres"
            "-h"
            "localhost"
          ];
          interval = "5s";
          retries = 10;
        };
        environment = {
          POSTGRES_HOST = "/var/run/postgresql";
          PGPORT = pg.port;
          POSTGRES_PORT = pg.port;
          POSTGRES_PASSWORD = env "POSTGRES_PASSWORD";
          POSTGRES_DB = pg.db;
          JWT_SECRET = env "JWT_SECRET";
          JWT_EXP = toString cfg.auth.jwtExpiry;
        };
        command = [
          "postgres"
          "-c"
          "config_file=/etc/postgresql/postgresql.conf"
          "-c"
          "log_min_messages=fatal"
        ]
        ++ lib.flatten (
          lib.mapAttrsToList (n: v: [
            "-c"
            "${n}='${v}'"
          ]) cfg.postgres.appSettings
        );
      };

      kong = baseService images.kong // {
        container_name = "supabase-kong";
        ports = [
          "${toString cfg.kong.httpPort}:8000/tcp"
          "${toString cfg.kong.httpsPort}:8443/tcp"
        ];
        volumes = [ "${secretsPrefix}-kong.yml:/home/kong/kong.yml:ro" ];
        environment = {
          KONG_DATABASE = "off";
          KONG_DECLARATIVE_CONFIG = "/home/kong/kong.yml";
          KONG_DNS_ORDER = "LAST,A,CNAME";
          KONG_PLUGINS = "request-transformer,cors,key-auth,acl,basic-auth,request-termination,ip-restriction";
          KONG_NGINX_PROXY_PROXY_BUFFER_SIZE = "160k";
          KONG_NGINX_PROXY_PROXY_BUFFERS = "64 160k";
          KONG_UPSTREAM_KEEPALIVE_POOL_SIZE = "60";
          KONG_UPSTREAM_KEEPALIVE_MAX_REQUESTS = "100";
          KONG_NGINX_PROXY_PROXY_READ_TIMEOUT = "30s";
          KONG_NGINX_PROXY_PROXY_SEND_TIMEOUT = "30s";
          SUPABASE_ANON_KEY = env "ANON_KEY";
          SUPABASE_SERVICE_KEY = env "SERVICE_ROLE_KEY";
          DASHBOARD_USERNAME = cfg.dashboardUsername;
          DASHBOARD_PASSWORD = env "DASHBOARD_PASSWORD";
        };
      };

      auth = baseService images.auth // {
        container_name = "supabase-auth";
        healthcheck = wgetHealth "http://localhost:9999/health";
        environment = {
          GOTRUE_API_HOST = "0.0.0.0";
          GOTRUE_API_PORT = "9999";
          API_EXTERNAL_URL = apiExternalUrl;
          GOTRUE_DB_DRIVER = "postgres";
          GOTRUE_DB_DATABASE_URL = dbUrl "supabase_auth_admin";
          GOTRUE_SITE_URL = cfg.siteUrl;
          GOTRUE_URI_ALLOW_LIST = lib.concatStringsSep "," cfg.auth.additionalRedirectUrls;
          GOTRUE_DISABLE_SIGNUP = lib.boolToString (!cfg.auth.enableSignup);
          GOTRUE_JWT_ADMIN_ROLES = "service_role";
          GOTRUE_JWT_AUD = "authenticated";
          GOTRUE_JWT_DEFAULT_GROUP_NAME = "authenticated";
          GOTRUE_JWT_EXP = toString cfg.auth.jwtExpiry;
          GOTRUE_JWT_SECRET = env "JWT_SECRET";
          GOTRUE_EXTERNAL_EMAIL_ENABLED = "true";
          GOTRUE_EXTERNAL_ANONYMOUS_USERS_ENABLED = lib.boolToString cfg.auth.enableAnonymousUsers;
          GOTRUE_MAILER_AUTOCONFIRM = lib.boolToString cfg.auth.enableEmailAutoconfirm;
          GOTRUE_MAILER_OTP_EXP = toString cfg.auth.otpExpiry;
          GOTRUE_MAILER_EXTERNAL_HOSTS = cfg.domain;
          GOTRUE_RATE_LIMIT_EMAIL_SENT = toString cfg.auth.rateLimitEmailSent;
          GOTRUE_MAILER_URLPATHS_CONFIRMATION = cfg.auth.mailerUrlPaths.confirmation;
          GOTRUE_MAILER_URLPATHS_INVITE = cfg.auth.mailerUrlPaths.invite;
          GOTRUE_MAILER_URLPATHS_RECOVERY = cfg.auth.mailerUrlPaths.recovery;
          GOTRUE_MAILER_URLPATHS_EMAIL_CHANGE = cfg.auth.mailerUrlPaths.emailChange;
          GOTRUE_EXTERNAL_PHONE_ENABLED = "false";
          GOTRUE_SMS_AUTOCONFIRM = "false";
        }
        // lib.optionalAttrs (cfg.smtpConfigFile != null) {
          GOTRUE_SMTP_ADMIN_EMAIL = env "SMTP_ADMIN_EMAIL";
          GOTRUE_SMTP_HOST = env "SMTP_HOST";
          GOTRUE_SMTP_PORT = env "SMTP_PORT";
          GOTRUE_SMTP_USER = env "SMTP_USER";
          GOTRUE_SMTP_PASS = env "SMTP_PASSWORD";
          GOTRUE_SMTP_SENDER_NAME = env "SMTP_SENDER_NAME";
        };
      };

      rest = baseService images.rest // {
        container_name = "supabase-rest";
        command = [ "postgrest" ];
        environment = {
          PGRST_DB_URI = dbUrl "authenticator";
          PGRST_DB_SCHEMAS = lib.concatStringsSep "," cfg.rest.dbSchemas;
          PGRST_DB_ANON_ROLE = "anon";
          PGRST_JWT_SECRET = env "JWT_SECRET";
          PGRST_DB_USE_LEGACY_GUCS = "false";
          PGRST_APP_SETTINGS_JWT_SECRET = env "JWT_SECRET";
          PGRST_APP_SETTINGS_JWT_EXP = toString cfg.auth.jwtExpiry;
        };
      };

      realtime = baseService images.realtime // {
        container_name = "realtime-dev.supabase-realtime";
        healthcheck = healthcheck {
          test = [
            "CMD-SHELL"
            "curl -sSfL --head -o /dev/null -H \"Authorization: Bearer ${env "ANON_KEY"}\" http://localhost:4000/api/tenants/realtime-dev/health"
          ];
        };
        environment = {
          PORT = "4000";
          DB_HOST = pg.host;
          DB_PORT = pg.port;
          DB_USER = "supabase_admin";
          DB_PASSWORD = env "POSTGRES_PASSWORD";
          DB_NAME = pg.db;
          DB_AFTER_CONNECT_QUERY = "SET search_path TO _realtime";
          DB_ENC_KEY = "supabaserealtime";
          API_JWT_SECRET = env "JWT_SECRET";
          SECRET_KEY_BASE = env "SECRET_KEY_BASE";
          ERL_AFLAGS = "-proto_dist inet_tcp";
          DNS_NODES = "''";
          RLIMIT_NOFILE = "10000";
          APP_NAME = "realtime";
          SEED_SELF_HOST = "true";
          RUN_JANITOR = "true";
        };
      };

      storage = baseService images.storage // {
        container_name = "supabase-storage";
        volumes = [ "${cfg.stateDir}/storage:/var/lib/storage" ];
        healthcheck = wgetHealth "http://storage:5000/status";
        depends_on = {
          rest.condition = "service_started";
          imgproxy.condition = "service_started";
        };
        environment = {
          ANON_KEY = env "ANON_KEY";
          SERVICE_KEY = env "SERVICE_ROLE_KEY";
          POSTGREST_URL = "http://rest:3000";
          PGRST_JWT_SECRET = env "JWT_SECRET";
          DATABASE_URL = dbUrl "supabase_storage_admin";
          FILE_SIZE_LIMIT = cfg.storage.fileSizeLimit;
          STORAGE_BACKEND = cfg.storage.backend;
          TENANT_ID = cfg.storage.tenantId;
          REQUEST_ALLOW_X_FORWARDED_PATH = "true";
          ENABLE_IMAGE_TRANSFORMATION = "true";
          IMGPROXY_URL = "http://imgproxy:5001";
        }
        // (
          if cfg.storage.backend == "file" then
            { FILE_STORAGE_BACKEND_PATH = "/var/lib/storage"; }
          else
            {
              REGION = cfg.storage.s3.region;
              GLOBAL_S3_BUCKET = cfg.storage.s3.bucket;
              AWS_ACCESS_KEY_ID = env "AWS_ACCESS_KEY_ID";
              AWS_SECRET_ACCESS_KEY = env "AWS_SECRET_ACCESS_KEY";
            }
            // lib.optionalAttrs (cfg.storage.s3.endpoint != "") {
              GLOBAL_S3_ENDPOINT = cfg.storage.s3.endpoint;
            }
            // lib.optionalAttrs cfg.storage.s3.forcePathStyle {
              GLOBAL_S3_FORCE_PATH_STYLE = "true";
            }
        );
      };

      imgproxy = (removeAttrs (baseService images.imgproxy) [ "extra_hosts" ]) // {
        container_name = "supabase-imgproxy";
        volumes = [ "${cfg.stateDir}/storage:/var/lib/storage" ];
        healthcheck = healthcheck {
          test = [
            "CMD"
            "imgproxy"
            "health"
          ];
        };
        environment = {
          IMGPROXY_BIND = ":5001";
          IMGPROXY_LOCAL_FILESYSTEM_ROOT = "/";
          IMGPROXY_USE_ETAG = "true";
          IMGPROXY_ENABLE_WEBP_DETECTION = "true";
        };
      };

      meta = baseService images.meta // {
        container_name = "supabase-meta";
        environment = {
          PG_META_PORT = "8080";
          PG_META_DB_HOST = pg.host;
          PG_META_DB_PORT = pg.port;
          PG_META_DB_NAME = pg.db;
          PG_META_DB_USER = "supabase_admin";
          PG_META_DB_PASSWORD = env "POSTGRES_PASSWORD";
          CRYPTO_KEY = env "PG_META_CRYPTO_KEY";
        };
      };

      supavisor = baseService images.supavisor // {
        container_name = "supabase-pooler";
        ports = [ "6543:6543" ];
        volumes = [ "${secretsPrefix}-pooler.exs:/etc/pooler/pooler.exs:ro" ];
        healthcheck = curlHealth "http://127.0.0.1:4000/api/health" // {
          interval = "10s";
          retries = 5;
        };
        command = [
          "/bin/sh"
          "-c"
          "/app/bin/migrate && /app/bin/supavisor eval \"$(cat /etc/pooler/pooler.exs)\" && /app/bin/server"
        ];
        environment = {
          PORT = "4000";
          POSTGRES_PORT = pg.port;
          POSTGRES_DB = pg.db;
          POSTGRES_PASSWORD = env "POSTGRES_PASSWORD";
          DATABASE_URL = "ecto://supabase_admin:${env "POSTGRES_PASSWORD"}@${pg.host}:${pg.port}/_supabase";
          CLUSTER_POSTGRES = "true";
          SECRET_KEY_BASE = env "SECRET_KEY_BASE";
          VAULT_ENC_KEY = env "VAULT_ENC_KEY";
          API_JWT_SECRET = env "JWT_SECRET";
          METRICS_JWT_SECRET = env "JWT_SECRET";
          REGION = "local";
          ERL_AFLAGS = "-proto_dist inet_tcp";
          POOLER_TENANT_ID = cfg.storage.tenantId;
          POOLER_DEFAULT_POOL_SIZE = toString cfg.pooler.defaultPoolSize;
          POOLER_MAX_CLIENT_CONN = toString cfg.pooler.maxClientConn;
          POOLER_POOL_MODE = "transaction";
        };
      };
    }
    // lib.optionalAttrs cfg.studio.enable {
      studio = baseService images.studio // {
        container_name = "supabase-studio";
        ports = [ "127.0.0.1:3000:3000" ];
        healthcheck = healthcheck {
          test = [
            "CMD"
            "node"
            "-e"
            "fetch('http://studio:3000/api/platform/profile').then((r) => {if (r.status !== 200) throw new Error(r.status)})"
          ];
          timeout = "10s";
        };
        environment = {
          HOSTNAME = "::";
          STUDIO_PG_META_URL = "http://meta:8080";
          POSTGRES_PORT = pg.port;
          POSTGRES_HOST = pg.host;
          POSTGRES_DB = pg.db;
          POSTGRES_PASSWORD = env "POSTGRES_PASSWORD";
          PG_META_CRYPTO_KEY = env "PG_META_CRYPTO_KEY";
          DEFAULT_ORGANIZATION_NAME = "Default Organization";
          DEFAULT_PROJECT_NAME = "Default Project";
          SUPABASE_URL = "http://kong:8000";
          SUPABASE_PUBLIC_URL = apiExternalUrl;
          SUPABASE_ANON_KEY = env "ANON_KEY";
          SUPABASE_SERVICE_KEY = env "SERVICE_ROLE_KEY";
          AUTH_JWT_SECRET = env "JWT_SECRET";
          NEXT_PUBLIC_ENABLE_LOGS = "false";
        };
      };
    };
  };

  dockerComposeFile = pkgs.writeText "docker-compose.yml" (builtins.toJSON dockerComposeConfig);

  # ── Pooler config template ──────────────────────────────────────────

  poolerTemplate = pkgs.writeText "pooler.exs.template" ''
    {:ok, _} = Application.ensure_all_started(:supavisor)

    {:ok, version} =
      case Supavisor.Repo.query!("select version()") do
        %{rows: [[ver]]} -> Supavisor.Helpers.parse_pg_version(ver)
        _ -> nil
      end

    params = %{
      "external_id" => "default",
      "db_host" => "${cfg.postgres.host}",
      "db_port" => "${toString cfg.postgres.port}",
      "db_database" => "${cfg.postgres.database}",
      "require_user" => false,
      "auth_query" => "SELECT * FROM pgbouncer.get_auth($1)",
      "default_max_clients" => ${toString cfg.pooler.maxClientConn},
      "default_pool_size" => ${toString cfg.pooler.defaultPoolSize},
      "default_parameter_status" => %{"server_version" => version},
      "users" => [%{
        "db_user" => "pgbouncer",
        "db_password" => "$POSTGRES_PASSWORD",
        "mode_type" => "transaction",
        "pool_size" => ${toString cfg.pooler.defaultPoolSize},
        "is_manager" => true
      }]
    }

    if !Supavisor.Tenants.get_tenant_by_external_id(params["external_id"]) do
      {:ok, _} = Supavisor.Tenants.create_tenant(params)
    end
  '';

  # ── Env files for docker compose ────────────────────────────────────

  s3 = cfg.storage.s3;

  envFiles =
    map (name: "${secretsPrefix}-${name}.variant") secretNames
    ++ [ "${secretsPrefix}-service-role-key.variant" ]
    ++ lib.optional (
      s3.accessKeyIdFile != null && s3.secretAccessKeyFile != null
    ) "${secretsPrefix}-s3-credentials.env"
    ++ lib.optional (cfg.smtpConfigFile != null) cfg.smtpConfigFile;

  # ── Image loading script ────────────────────────────────────────────

  loadImagesScript = pkgs.writeShellScript "supabase-load-images" ''
    set -e
    ${lib.concatMapStringsSep "\n" (
      name:
      let
        img = images.${name};
        ref = "${img.imageName}@${img.imageDigest}";
      in
      ''
        if ! ${lib.getExe pkgs.docker} image inspect "${ref}" &>/dev/null; then
          echo "Loading ${name}: ${ref}..."
          ${lib.getExe pkgs.docker} load -i ${img}
        else
          echo "Already loaded ${name}: ${ref}"
        fi
      ''
    ) (builtins.attrNames (lib.filterAttrs (_: lib.isDerivation) images))}
  '';

  # ── Config generation script ────────────────────────────────────────

  kongYmlTemplate = "${cfg.supabaseSource}/docker/volumes/api/kong.yml";

  generateConfigScript = pkgs.writeShellScript "supabase-generate-config" ''
    set -euo pipefail
    ANON_KEY=$(< ${secretsPrefix}-anon-key)
    SERVICE_ROLE_KEY=$(< ${secretsPrefix}-service-role-key)
    DASHBOARD_PASSWORD=$(< ${secretsPrefix}-dashboard-password)
    export POSTGRES_PASSWORD=$(< ${secretsPrefix}-postgres-password)

    ${lib.getExe pkgs.gnused} \
      -e "s|\$SUPABASE_ANON_KEY|$ANON_KEY|g" \
      -e "s|\$SUPABASE_SERVICE_KEY|$SERVICE_ROLE_KEY|g" \
      -e "s|\$DASHBOARD_PASSWORD|$DASHBOARD_PASSWORD|g" \
      -e "s|\$DASHBOARD_USERNAME|${cfg.dashboardUsername}|g" \
      ${kongYmlTemplate} > ${secretsPrefix}-kong.yml

    ${lib.getExe pkgs.envsubst} < ${poolerTemplate} > ${secretsPrefix}-pooler.exs

    ${lib.optionalString (s3.accessKeyIdFile != null && s3.secretAccessKeyFile != null) ''
      echo "AWS_ACCESS_KEY_ID=$(< ${s3.accessKeyIdFile})" > ${secretsPrefix}-s3-credentials.env
      echo "AWS_SECRET_ACCESS_KEY=$(< ${s3.secretAccessKeyFile})" >> ${secretsPrefix}-s3-credentials.env
    ''}
  '';

  # ── Migration script ────────────────────────────────────────────────

  migrationScript =
    let
      backendConfig = builtins.fromTOML (builtins.readFile "${cfg.migrations.source}/config.toml");
      productionConfig = lib.recursiveUpdate backendConfig {
        db = {
          port = cfg.postgres.port;
          major_version = 17;
          pooler.enabled = true;
          pooler.port = 6543;
        };
        studio.api_url = "http://localhost";
      };
      tomlFormat = pkgs.formats.toml { };
      configFile = tomlFormat.generate "config.toml" productionConfig;
      supabaseProject = pkgs.runCommand "supabase-project" { } ''
        mkdir -p $out/supabase/migrations $out/seeds
        cp -r ${cfg.migrations.source}/migrations/* $out/supabase/migrations/
        cp ${cfg.migrations.source}/seed.sql $out/seed.sql 2>/dev/null || true
        cp -r ${cfg.migrations.source}/seeds/* $out/seeds/ 2>/dev/null || true
        ln -s ${configFile} $out/config.toml
      '';
      seedsAppliedFile = "${cfg.stateDir}/.seeds-applied";
      seedPaths = productionConfig.db.seed.sql_paths or [ ];
      seedEnabled = productionConfig.db.seed.enabled or false;
      seedProcessingCode = lib.concatMapStringsSep "\n" (pattern: ''
        for seed_file in ${pattern}; do
          if [ -f "$seed_file" ]; then
            if ! grep -Fxq "$seed_file" "${seedsAppliedFile}"; then
              echo "Running new seed: $seed_file"
              ${lib.getExe' pkgs.postgresql "psql"} "$DB_URL" -f "$seed_file"
              echo "$seed_file" >> "${seedsAppliedFile}"
            else
              echo "Already applied: $seed_file"
            fi
          fi
        done
      '') seedPaths;
    in
    pkgs.writeShellScript "run-supabase-migrations" ''
      set -euo pipefail

      export PGPASSWORD=$(< ${secretsPrefix}-postgres-password)
      export PGSSLMODE=disable
      DB_URL="postgresql://postgres:$PGPASSWORD@localhost:${pg.port}/${pg.db}?sslmode=disable"

      cd ${supabaseProject}

      if ! ${lib.getExe' pkgs.postgresql "psql"} "$DB_URL" -c "SELECT 1" > /dev/null 2>&1; then
        echo "ERROR: Cannot connect to database"
        exit 1
      fi

      touch "${seedsAppliedFile}"

      echo "=== Running migrations ==="
      ${lib.getExe pkgs.supabase-cli} db push --db-url "$DB_URL"

      echo "=== Syncing JWT_SECRET to database ==="
      JWT_SECRET=$(< ${secretsPrefix}-jwt-secret)
      PGPASS=$(< ${secretsPrefix}-postgres-password)
      ${lib.getExe pkgs.docker} exec supabase-db \
        env PGPASSWORD="$PGPASS" \
        psql -U supabase_admin -d postgres \
        -c "ALTER DATABASE postgres SET \"app.settings.jwt_secret\" TO '$JWT_SECRET';"
      echo "JWT_SECRET synced"

      ${lib.optionalString seedEnabled ''
        echo "=== Checking seed files ==="
        ${seedProcessingCode}
        echo "=== Seeding complete ==="
      ''}

      echo "=== Migration complete ==="
    '';

  # ── Tmpfiles helper ─────────────────────────────────────────────────

  mkDir = {
    d = {
      mode = "0750";
      user = "root";
      group = "docker";
    };
  };
in
{
  options = namespaced __curPos {
    supabaseSource = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to the upstream supabase repository source.
        Provides init SQL scripts and the Kong gateway config template.
        Typically a flake input: `supabase = { url = "github:supabase/supabase/<rev>"; flake = false; }`
      '';
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/supabase";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "supabase.example.com";
    };

    siteUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://supabase.example.com";
    };

    postgres = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "db";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 5432;
      };
      database = lib.mkOption {
        type = lib.types.str;
        default = "postgres";
        readOnly = true;
        description = "Database name — must be 'postgres' as Supabase init scripts hardcode this value";
      };
      appSettings = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Custom PostgreSQL app.* settings accessible via current_setting()";
      };
    };

    kong = {
      httpPort = lib.mkOption {
        type = lib.types.port;
        default = 8000;
      };
      httpsPort = lib.mkOption {
        type = lib.types.port;
        default = 8443;
      };
    };

    studio.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    dashboardUsername = lib.mkOption {
      type = lib.types.str;
      default = "supabase";
    };

    auth = {
      enableSignup = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      enableAnonymousUsers = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      enableEmailAutoconfirm = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      jwtExpiry = lib.mkOption {
        type = lib.types.int;
        default = 3600;
      };
      otpExpiry = lib.mkOption {
        type = lib.types.int;
        default = 3600;
        description = "OTP expiry time in seconds";
      };
      rateLimitEmailSent = lib.mkOption {
        type = lib.types.int;
        default = 10;
        description = "Maximum number of emails sent per hour";
      };
      additionalRedirectUrls = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      mailerUrlPaths = {
        confirmation = lib.mkOption {
          type = lib.types.str;
          default = "/auth/v1/verify";
        };
        invite = lib.mkOption {
          type = lib.types.str;
          default = "/auth/v1/verify";
        };
        recovery = lib.mkOption {
          type = lib.types.str;
          default = "/auth/v1/verify";
        };
        emailChange = lib.mkOption {
          type = lib.types.str;
          default = "/auth/v1/verify";
        };
      };
    };

    smtpConfigFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to SMTP config file with environment variables:
        SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASSWORD, SMTP_SENDER_NAME, SMTP_ADMIN_EMAIL
      '';
    };

    storage = {
      fileSizeLimit = lib.mkOption {
        type = lib.types.str;
        default = "52428800";
      };
      backend = lib.mkOption {
        type = lib.types.enum [
          "file"
          "s3"
        ];
        default = "file";
      };
      tenantId = lib.mkOption {
        type = lib.types.str;
        default = "default";
      };
      s3 = {
        bucket = lib.mkOption {
          type = lib.types.str;
          default = "";
        };
        region = lib.mkOption {
          type = lib.types.str;
          default = "";
        };
        endpoint = lib.mkOption {
          type = lib.types.str;
          default = "";
        };
        forcePathStyle = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
        accessKeyIdFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
        };
        secretAccessKeyFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
        };
      };
    };

    functions.verifyJwt = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    rest.dbSchemas = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "public"
        "storage"
        "graphql_public"
      ];
    };

    pooler = {
      defaultPoolSize = lib.mkOption {
        type = lib.types.int;
        default = 20;
      };
      maxClientConn = lib.mkOption {
        type = lib.types.int;
        default = 100;
      };
    };

    migrations = {
      enable = lib.mkEnableOption "Supabase database migrations";
      source = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to migration source directory (must contain config.toml and migrations/)";
      };
    };

    extraRequires = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra systemd units the Supabase stack requires before starting";
    };
  };

  config = lib.mkIf (cfg.supabaseSource != null) {
    assertions = [
      {
        assertion = cfg.migrations.enable -> cfg.migrations.source != null;
        message = "foundrix.services.supabase.migrations.source must be set when migrations are enabled";
      }
    ];

    foundrix.services.secrets = secretsConfig;

    systemd.tmpfiles.settings."10-supabase" = {
      "${cfg.stateDir}" = mkDir;
      "${cfg.stateDir}/db" = mkDir;
      "${cfg.stateDir}/storage" = mkDir;
      "${cfg.stateDir}/functions" = mkDir;
    };

    systemd.services.supabase-generate-service-role-key = {
      description = "Generate Supabase service role JWT";
      requires = [ "generate-secret-supabase-jwt-secret.service" ];
      after = [ "generate-secret-supabase-jwt-secret.service" ];
      requiredBy = [ "supabase-stack.service" ];
      before = [ "supabase-stack.service" ];
      unitConfig.ConditionPathExists = "!${secretsPrefix}-service-role-key";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = generateServiceRoleKey;
      };
    };

    systemd.services.supabase-config = {
      description = "Generate Supabase config files";
      requires = secretServiceUnits;
      after = secretServiceUnits;
      wantedBy = [ "supabase-stack.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = generateConfigScript;
        RemainAfterExit = true;
      };
    };

    systemd.services.supabase-stack = {
      description = "Supabase Docker Compose stack";
      requires = [
        "docker.service"
        "supabase-config.service"
      ]
      ++ cfg.extraRequires;
      wants = [ "network-online.target" ];
      after = [
        "docker.service"
        "supabase-config.service"
        "network-online.target"
      ]
      ++ cfg.extraRequires;
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.docker ];
      serviceConfig = {
        Type = "simple";
        WorkingDirectory = cfg.stateDir;
        ExecStartPre = loadImagesScript;
        ExecStart = "${lib.getExe pkgs.docker} compose ${
          lib.concatMapStringsSep " " (f: "--env-file ${f}") envFiles
        } -f ${dockerComposeFile} up --remove-orphans";
        ExecStop = "${lib.getExe pkgs.docker} compose -f ${dockerComposeFile} down";
        TimeoutStartSec = "30min";
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };

    systemd.services.supabase-migrations = lib.mkIf cfg.migrations.enable {
      description = "Apply Supabase migrations";
      after = [
        "supabase-stack.service"
        "docker.service"
      ];
      requires = [ "supabase-stack.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.postgresql
        pkgs.supabase-cli
        pkgs.docker
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = migrationScript;
        Restart = "on-failure";
        RestartSec = "10s";
        TimeoutStartSec = "300s";
      };
      preStart = ''
        echo "Waiting for PostgreSQL to be ready..."
        for i in {1..60}; do
          if ${lib.getExe pkgs.docker} exec supabase-db pg_isready -U postgres > /dev/null 2>&1; then
            echo "PostgreSQL is ready!"
            break
          fi
          echo "Waiting for PostgreSQL... ($i/60)"
          sleep 2
        done

        echo "Waiting for auth service to be healthy..."
        for i in {1..60}; do
          if ${lib.getExe pkgs.docker} exec supabase-auth wget -q --spider http://localhost:9999/health 2>/dev/null; then
            echo "Auth service is healthy!"
            sleep 2
            exit 0
          fi
          echo "Waiting for auth... ($i/60)"
          sleep 2
        done
        echo "ERROR: Auth service did not become healthy in time"
        exit 1
      '';
    };
  };
}
