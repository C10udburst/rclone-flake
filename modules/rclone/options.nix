# modules/rclone/options.nix
{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib) mkOption mkEnableOption types;

  mountSubmodule = { name, ... }: {
    options = {
      remote = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "google-drive:/media";
        description = ''
          The remote storage endpoint to mount. Optional if union mount is enabled.
        '';
      };

      mountPoint = mkOption {
        type = types.str;
        example = "/mnt/media";
        description = "Absolute local directory where the remote will be mounted.";
      };

      # Permissions & Ownership
      user = mkOption {
        type = types.str;
        default = "root";
        description = "User under which the mount runs and owns the mountpoint.";
      };

      group = mkOption {
        type = types.str;
        default = "root";
        description = "Group under which the mount runs and owns the mountpoint.";
      };

      allowOther = mkOption {
        type = types.bool;
        default = false;
        description = "Allow other non-root users to access the mount (FUSE).";
      };

      allowNonEmpty = mkOption {
        type = types.bool;
        default = false;
        description = "Allow mounting over a non-empty directory.";
      };

      readOnly = mkOption {
        type = types.bool;
        default = false;
        description = "Mount the filesystem in read-only mode.";
      };

      defaultPermissions = mkOption {
        type = types.bool;
        default = false;
        description = "Enforce kernel permission checking on the mount.";
      };

      umask = mkOption {
        type = types.str;
        default = "022";
        description = "Filesystem umask for the mount.";
      };

      uid = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Override file UID presented to the OS.";
      };

      gid = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Override file GID presented to the OS.";
      };

      # VFS Cache
      vfsCacheMode = mkOption {
        type = types.enum [
          "off"
          "minimal"
          "writes"
          "full"
        ];
        default = "writes";
        description = "VFS cache mode for rclone.";
      };

      vfsCacheMaxAge = mkOption {
        type = types.str;
        default = "24h";
        description = "Max age of objects in the VFS cache.";
      };

      vfsCacheMaxSize = mkOption {
        type = types.str;
        default = "50G";
        description = "Max size of the VFS cache (e.g. 50G, 100M).";
      };

      vfsCachePollInterval = mkOption {
        type = types.str;
        default = "1m";
        description = "Interval to check and purge old VFS cache items.";
      };

      vfsReadChunkSize = mkOption {
        type = types.str;
        default = "128M";
        description = "Initial read chunk size.";
      };

      vfsReadChunkSizeLimit = mkOption {
        type = types.str;
        default = "off";
        description = "Max chunk size for reading files.";
      };

      vfsWriteBack = mkOption {
        type = types.str;
        default = "5s";
        description = "Delay before writing modified files back to the cloud.";
      };

      vfsReadAhead = mkOption {
        type = types.str;
        default = "128M";
        description = "Extra read ahead buffer.";
      };

      # Performance & Cache Timings
      dirCacheTime = mkOption {
        type = types.str;
        default = "72h";
        description = "Time to cache directory listings in memory.";
      };

      pollInterval = mkOption {
        type = types.str;
        default = "1m";
        description = "Polling interval for remote changes.";
      };

      attrTimeout = mkOption {
        type = types.str;
        default = "1s";
        description = "Attribute cache timeout.";
      };

      bufferSize = mkOption {
        type = types.str;
        default = "16M";
        description = "In-memory file read buffer per open file.";
      };

      # Bandwidth & Network
      bwlimit = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "50M";
        description = "Bandwidth limit (e.g. '10M', '50M:100M').";
      };

      transfers = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Number of parallel file transfers.";
      };

      checkers = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Number of parallel metadata checkers.";
      };

      lowLevelRetries = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Number of low level retries.";
      };

      # Logging
      logLevel = mkOption {
        type = types.enum [
          "DEBUG"
          "INFO"
          "NOTICE"
          "ERROR"
        ];
        default = "NOTICE";
        description = "Rclone log level.";
      };

      logFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to dedicated log file.";
      };

      # Remote Control (RC)
      rc = {
        enable = mkEnableOption "rclone remote control API server";
        address = mkOption {
          type = types.str;
          default = "127.0.0.1:5572";
          description = "Address for RC server.";
        };
        noAuth = mkOption {
          type = types.bool;
          default = false;
          description = "Disable authentication for the RC API server.";
        };
      };

      # Secrets & Environment Integration
      configFile = mkOption {
        type = types.nullOr (types.either types.path types.str);
        default = null;
        description = "Mount-specific rclone.conf override path.";
      };

      environmentFile = mkOption {
        type = types.nullOr (types.either types.path types.str);
        default = null;
        example = "/run/agenix/rclone-media.env";
        description = "Systemd EnvironmentFile containing token/auth secrets.";
      };

      environment = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "Additional environment variables passed to the mount service.";
      };

      # Union Submodule
      union = {
        enable = mkEnableOption "local-write overlay / union mount";

        remote = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "dropbox:/backups";
          description = "Upstream cloud remote to read from.";
        };

        localWriteDir = mkOption {
          type = types.str;
          default = "/var/lib/rclone/local-layers/${name}";
          description = "Local directory where newly created/modified files are written.";
        };

        localPolicy = mkOption {
          type = types.str;
          default = "epff";
          description = "Union policy for local write layer (default: 'epff').";
        };

        remotePolicy = mkOption {
          type = types.str;
          default = "ro";
          description = "Union policy for cloud upstream layer (default: 'ro').";
        };

        actionPolicy = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Union action policy (e.g. 'all', 'epall').";
        };

        createPolicy = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Union creation policy (e.g. 'mfs', 'epff').";
        };

        searchPolicy = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Union search policy (e.g. 'ff').";
        };

        minFreeSpace = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "10G";
          description = "Minimum free disk space required on local layer.";
        };

        extraConfig = mkOption {
          type = types.attrsOf types.str;
          default = { };
          description = "Additional key-value pairs for the union remote section.";
        };
      };

      extraArgs = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [
          "--fast-list"
          "--links"
        ];
        description = "Additional raw CLI arguments passed to `rclone mount`.";
      };
    };
  };

in
{
  options.services.rclone = {
    enable = mkEnableOption "rclone mount management framework";

    package = mkOption {
      type = types.package;
      default = pkgs.rclone;
      defaultText = lib.literalExpression "pkgs.rclone";
      description = "The rclone package to use for all mounts.";
    };

    globalConfigFile = mkOption {
      type = types.nullOr (types.either types.path types.str);
      default = null;
      example = "/var/lib/rclone/rclone.conf";
      description = ''
        Path to an existing, external rclone configuration file.
        Can point to an Agenix or Sops secret path.
      '';
    };

    globalEnvironmentFile = mkOption {
      type = types.nullOr (types.either types.path types.str);
      default = null;
      example = "/run/agenix/rclone-global.env";
      description = "Global systemd EnvironmentFile containing tokens and secrets.";
    };

    mounts = mkOption {
      type = types.attrsOf (types.submodule mountSubmodule);
      default = { };
      description = "Declarative specification of rclone mounts.";
    };
  };
}
