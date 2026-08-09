# Dump PostgreSQL databases onto the state subvolume, normally /var.
#
# A snapshot of a running database is crash-consistent: PostgreSQL recovers
# from it the way it recovers from a power cut, which is a real guarantee but
# not a portable one. The copied data directory only replays on a server of the
# same major version, on the same architecture, with the same page layout — and
# a single torn relation takes the whole cluster with it. A dump is a logical
# copy that restores into any server that can read it, and it is the thing
# somebody actually wants at three in the morning.
#
# The dumps land on the subvolume itself, which is what makes them useful in
# two independent ways. With a backup configured they are carried by the same
# snapshot as everything else and need no transport of their own, so they are
# taken as part of each run, immediately before the snapshot. With no backup
# configured they are still worth having — a restorable copy of the database
# beside the cluster it came from — so this module keeps its own schedule and
# does not require a destination, or the replication engine, to exist at all.
# `onCalendar` is what switches between those two, and its default picks the
# right one.
#
# There is no rotation here, and deliberately so: each database is dumped to
# one file that is overwritten on every run. Where a backup exists, the older
# dumps are the ones inside older snapshots, which is precisely what the
# snapshots are for; a second history beside the first would only fill the
# subvolume with copies no retention policy knows about. Where none exists,
# what is wanted is a current dump, and a pile of old ones on the same disk as
# the cluster protects against nothing.
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
      description = "Whether to dump databases onto the state subvolume.";
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
        Where the dumps are written. Must be on the state subvolume: a dump
        anywhere else is lost with the disk it was meant to survive, and where
        a backup exists it would never reach a snapshot either.
      '';
    };

    onCalendar = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = if backup.enable then null else "daily";
      defaultText = lib.literalMD ''
        `null` when a backup is configured, since the dumps are then taken as
        part of each run; `"daily"` when none is, so they are taken anyway.
      '';
      description = ''
        Schedule of the dumps' own timer, in systemd calendar format.

        `null` means no timer: something else decides when to dump, which is
        what a configured backup does — it pulls the dump in and waits for it,
        so the snapshot carries one taken moments earlier.

        Set it alongside a backup only to want dumps more often than backups
        are taken. Both triggers then apply.
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
          which is outside ${backup.mountPoint}. The dumps belong on the state
          subvolume: anywhere else they are lost with the disk they were meant
          to survive, and where a backup is configured they would never reach a
          snapshot either.
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
      description = "Dump PostgreSQL databases onto ${backup.mountPoint}";
      # With a backup configured, the run pulls this in and waits for it, so
      # the snapshot carries a dump taken moments earlier. Wants and not
      # Requires: a database that cannot be dumped is a reason to shout, and
      # not a reason to skip the filesystem backup as well.
      #
      # With no backup configured there is no such unit to attach to, and the
      # timer below is what takes the dumps instead.
      wantedBy = lib.optional backup.enable backup.runUnit;
      before = lib.optional backup.enable backup.runUnit;
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

    systemd.timers.backup-postgres-dump = lib.mkIf (cfg.onCalendar != null) {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        # A machine that was off at the scheduled time still gets a dump.
        Persistent = true;
      };
    };
  };
}
