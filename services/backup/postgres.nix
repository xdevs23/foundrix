# Dump PostgreSQL databases into the subvolume before it is snapshotted.
#
# A snapshot of a running database is crash-consistent: PostgreSQL recovers
# from it the way it recovers from a power cut, which is a real guarantee but
# not a portable one. The copied data directory only replays on a server of the
# same major version, on the same architecture, with the same page layout — and
# a single torn relation takes the whole cluster with it. A dump is a logical
# copy that restores into any server that can read it, and it is the thing
# somebody actually wants at three in the morning.
#
# So both go in the backup. The dumps are written inside the subvolume being
# backed up, which means they are carried by the same snapshot and need no
# transport of their own.
#
# There is no rotation here, and deliberately so: each database is dumped to
# one file that is overwritten on every run. Older dumps are the ones inside
# older snapshots, which is precisely what the snapshots are for. Keeping a
# second history beside the first would only fill the subvolume with copies the
# retention policy knows nothing about.
{
  config,
  lib,
  pkgs,
  foundrixModules,
  namespaced,
  namespacedCfg,
  ...
}:
let
  cfg = namespacedCfg __curPos;
  backup = config.foundrix.services.backup.btrfs;

  postgres = config.services.postgresql;
  pgDump = lib.getExe' postgres.package "pg_dump";
  mv = lib.getExe' pkgs.coreutils "mv";

  # Written to under a name that says it is incomplete and renamed once the
  # dump has finished. Without that, a dump interrupted part-way is
  # indistinguishable from a good one until somebody tries to restore it.
  partialFile = database: "${cfg.directory}/${database}.dump.partial";
  finalFile = database: "${cfg.directory}/${database}.dump";
in
{
  imports = [ foundrixModules.services.backup.btrfs ];

  options = namespaced __curPos {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.databases != [ ];
      defaultText = lib.literalMD "true once a database is listed";
      description = "Whether to dump databases into the subvolume before each backup run.";
    };

    databases = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Databases to dump. Each is written in PostgreSQL's custom format,
        which `pg_restore` reads and which compresses as it writes.
      '';
    };

    directory = lib.mkOption {
      type = lib.types.str;
      default = "${backup.mountPoint}/backup/postgres";
      defaultText = lib.literalExpression ''"''${foundrix.services.backup.btrfs.mountPoint}/backup/postgres"'';
      description = ''
        Where the dumps are written. Must be inside the subvolume being backed
        up, since being carried by its snapshot is the whole point.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = postgres.enable;
        message = ''
          foundrix.services.backup.postgres lists databases to dump, but this
          configuration runs no PostgreSQL server.
        '';
      }
      {
        assertion = lib.hasPrefix "${backup.mountPoint}/" cfg.directory;
        message = ''
          foundrix.services.backup.postgres.directory is ${cfg.directory},
          which is outside ${backup.mountPoint} — the dumps would never reach a
          snapshot, and the backup would carry nothing but the data directory.
        '';
      }
    ];

    # The dumps are a readable copy of everything in the databases, so they are
    # owned by the account that writes them and by nobody else.
    systemd.tmpfiles.settings.backup-postgres.${cfg.directory}.d = {
      mode = "0700";
      user = "postgres";
      group = "postgres";
    };

    systemd.services.backup-postgres-dump = {
      description = "Dump PostgreSQL databases into ${backup.mountPoint} for the backup";
      # Pulled in by the run and ordered before it. Wants and not Requires: a
      # database that cannot be dumped is a reason to shout, and not a reason
      # to skip the filesystem backup as well.
      wantedBy = [ backup.runUnit ];
      before = [ backup.runUnit ];
      after = [ "postgresql.service" ];
      unitConfig.RequiresMountsFor = [ backup.mountPoint ];

      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        Group = "postgres";
        # One dump per database, each renamed into place before the next
        # starts. systemd runs these in order and abandons the rest as soon as
        # one fails, so a failure is loud and never leaves a half-written file
        # under the name a restore would reach for.
        ExecStart = lib.concatMap (database: [
          "${pgDump} --format=custom --file=${partialFile database} ${database}"
          "${mv} -f ${partialFile database} ${finalFile database}"
        ]) cfg.databases;
      };
    };
  };
}
