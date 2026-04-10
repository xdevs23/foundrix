{
  lib,
  pkgs,
  config,
  namespaced,
  namespacedCfg,
  ...
}:
let
  cfg = namespacedCfg __curPos;

  databaseType = lib.types.submodule {
    options = {
      user = lib.mkOption {
        type = lib.types.str;
        description = "User allowed to connect to this database";
      };
      useCompliantPgPassFormat = lib.mkEnableOption "compliant libpq pgpass file format";
      adminPrivileges = lib.mkEnableOption "CREATEROLE and CREATEDB privileges for this database's user";
    };
  };

  databases = cfg.databases;
  dbNames = lib.attrNames databases;
  dbUsers = lib.unique (lib.flatten (map (db: db.user) (lib.attrValues databases)));

  secretName = username: "postgres-${username}-user-password";
  secret = username: config.foundrix.services.secrets.${secretName username};

  waitForPsql = pkgs.writeShellScript "wait-for-psql" ''
    until ${lib.getExe' config.services.postgresql.package "pg_isready"}; do sleep 0.1; done
  '';

  # Password permission services — grant read access to the generated
  # credential files so that both the database user and postgres can
  # authenticate.
  dbPwPermissionServices = builtins.listToAttrs (
    map (dbName: {
      name = "postgres-db-password-permission-grant@${dbName}";
      value =
        let
          user = databases.${dbName}.user;
          generatedPassword = secret user;
        in
        rec {
          description = "Grants permissions to DB passwords so that services can access ${dbName}";
          requires = [
            generatedPassword.service
          ];
          after = requires;

          unitConfig.StartLimitIntervalSec = 0;

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "root";

            ExecStart = pkgs.writeShellScript "" ''
              set -euo pipefail

              cred="${generatedPassword.path}"
              chown ${user} "$cred"
              ${lib.getExe' pkgs.acl "setfacl"} -m 'u:${user}:r--' "$cred"
              ${lib.getExe' pkgs.acl "setfacl"} -m 'u:postgres:r--' "$cred"
              ${lib.getExe' pkgs.acl "setfacl"} -m 'u:root:r--' "$cred"

              # Variant file (e.g. pgpass format) — use plain ownership
              # instead of ACLs, since tools like psql reject files where
              # traditional group bits are set (ACL mask side-effect).
              variant="${generatedPassword.variantPath}"
              if [ -f "$variant" ]; then
                chown ${user}:${user} "$variant"
                chmod 0600 "$variant"
              fi
            '';
          };
        };
    }) dbNames
  );

  # Password rotation services — set the PostgreSQL role password to the
  # value stored in the generated credential file.
  dbPwRotationServices = builtins.listToAttrs (
    map (username: {
      name = "postgres-db-rotate-user-password@${username}";
      value =
        let
          generatedPassword = secret username;
        in
        rec {
          description = "Rotate PostgreSQL password for the user ${username}";
          requires =
            [
              "postgresql.service"
              generatedPassword.service
            ]
            ++ lib.mapAttrsToList (name: _: "${name}.service") dbPwPermissionServices;
          after = requires ++ [ "postgresql-setup.service" ];

          unitConfig.StartLimitIntervalSec = 0;

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "postgres";
            Restart = "on-failure";

            ExecStartPre = waitForPsql;
            ExecStart = pkgs.writeShellScript "rotate-${username}-db-password" ''
              set -euo pipefail
              (
                ${lib.getExe' pkgs.util-linux "flock"} 9
                ${lib.getExe' config.services.postgresql.package "psql"} -d postgres -q -v ON_ERROR_STOP=1 \
                  -c "ALTER ROLE \"${username}\" WITH PASSWORD '$(< ${generatedPassword.path})';"
              ) 9>/run/postgresql/pw-rotation.lock
            '';
          };
        };
    }) dbUsers
  );

  # Database permission services — grant ownership and connect rights
  # after passwords have been rotated.
  dbGrantServices = builtins.listToAttrs (
    map (
      dbName:
      let
        user = databases.${dbName}.user;
      in
      {
        name = "postgres-db-grant-permissions@${dbName}";
        value = rec {
          description = "Grant CONNECT and public-schema rights on ${dbName} to ${user}";
          requires = lib.mapAttrsToList (name: _: "${name}.service") (
            dbPwRotationServices // dbPwPermissionServices
          );
          after = requires;

          unitConfig.StartLimitIntervalSec = 0;

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "postgres";
            Restart = "on-failure";

            ExecStartPre = waitForPsql;
            ExecStart = pkgs.writeShellScript "grant-${dbName}" ''
              set -euo pipefail

              ${lib.getExe' config.services.postgresql.package "psql"} -d postgres -v ON_ERROR_STOP=1 -c \
                "GRANT CONNECT ON DATABASE \"${dbName}\" TO \"${user}\";"

              ${lib.optionalString databases.${dbName}.adminPrivileges ''
              ${lib.getExe' config.services.postgresql.package "psql"} -d postgres -v ON_ERROR_STOP=1 -c \
                "ALTER ROLE \"${user}\" CREATEROLE CREATEDB;"
              ''}

              ${lib.getExe' config.services.postgresql.package "psql"} -d "${dbName}" -v ON_ERROR_STOP=1 <<SQL
                ALTER DATABASE "${dbName}" OWNER TO "${user}";

                \connect "${dbName}"
                ALTER SCHEMA public OWNER TO "${user}";

                GRANT USAGE ON SCHEMA public TO "postgres";
              SQL
            '';
          };
        };
      }
    ) dbNames
  );

  allPrerequisiteServices = dbPwRotationServices // dbPwPermissionServices // dbGrantServices;
in
{
  options = namespaced __curPos {
    databases = lib.mkOption {
      type = lib.types.attrsOf databaseType;
      default = { };
      description = "Databases to create and manage with automatic password rotation";
    };

    prerequisiteUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      default = lib.mapAttrsToList (name: _: "${name}.service") allPrerequisiteServices;
      description = "Systemd units that must complete before a database consumer can start";
    };
  };

  config = lib.mkIf (cfg.databases != { }) {
    services.postgresql = {
      enable = true;
      package = lib.mkOverride 900 pkgs.postgresql_17;

      ensureDatabases = dbNames;

      ensureUsers = map (name: {
        inherit name;
        ensureDBOwnership = false;
      }) dbUsers;

      authentication = lib.mkOverride 10 ''
${lib.concatMapStrings (
          db:
          let
            user = databases.${db}.user;
          in
          ''
            local  ${db}  ${user}  scram-sha-256
            local  ${db}  all  peer map=superuser_map
          ''
        ) dbNames}
        ${lib.concatMapStrings (user: ''
            local  postgres  ${user}  scram-sha-256
        '') dbUsers}
        local  sameuser  all  peer map=superuser_map
      '';

      identMap = ''
        superuser_map      root      postgres
        superuser_map      postgres  postgres
      '';
    };

    foundrix.services.secrets = builtins.listToAttrs (
      map (
        dbName:
        let
          username = databases.${dbName}.user;
          useCompliantPgPassFormat = databases.${dbName}.useCompliantPgPassFormat;
        in
        {
          name = secretName username;
          value =
            {
              owner = "postgres";
              persistent = false;
            }
            // lib.optionalAttrs useCompliantPgPassFormat {
              prefix = "*:*:${dbName}:${username}:";
            };
        }
      ) dbNames
    );

    systemd.services = allPrerequisiteServices;
  };
}
