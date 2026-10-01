# Production Recipes

Practical configuration recipes for common deployment patterns.

---

## 1. High-Performance Media Streaming (Plex / Jellyfin)

This configuration optimizes for fast stream startups, aggressive directory listing retention, and sequential read caching while avoiding cloud API throttling.

```nix
# /etc/nixos/modules/media-mount.nix
{ config, pkgs, ... }:

{
  services.rclone = {
    enable = true;
    globalConfigFile = config.age.secrets."rclone.conf".path;

    mounts."plex-media" = {
      remote = "gdrive-crypt:/Media";
      mountPoint = "/mnt/media";

      user = "media";
      group = "media";
      allowOther = true;

      # VFS Read Optimization
      vfsCacheMode = "full";
      vfsCacheMaxSize = "200G";
      vfsCacheMaxAge = "72h";
      vfsReadChunkSize = "64M";
      vfsReadChunkSizeLimit = "2G";
      vfsReadAhead = "256M";

      # Metadata Longevity (Reduces Drive API Queries)
      dirCacheTime = "168h";       # 7 days
      pollInterval = "1m";
      attrTimeout = "10s";
      bufferSize = "64M";

      # Limit concurrent operations to stay below API thresholds
      transfers = 4;
      checkers = 8;

      # Expose RC for manual cache invalidation
      rc = {
        enable = true;
        address = "127.0.0.1:5572";
        noAuth = true;
      };

      extraArgs = [
        "--fast-list"
        "--drive-skip-gdocs"
      ];
    };
  };

  users.users.media = {
    isSystemUser = true;
    group = "media";
  };
  users.groups.media = { };
}

```

---

## 2. Ephemeral Union / Local-Write Sync Architecture

This pattern presents cloud backups as a local filesystem. Reads come directly from the cloud backend, while modifications, deletes, and writes route to a fast local NVMe layer. A separate scheduled task can sync local changes back to the cloud.

```nix
# /etc/nixos/modules/backup-overlay.nix
{ config, pkgs, ... }:

{
  services.rclone = {
    enable = true;
    globalConfigFile = "/run/agenix/rclone.conf";

    mounts."cloud-workspace" = {
      mountPoint = "/mnt/workspace";
      allowOther = true;
      vfsCacheMode = "writes";

      union = {
        enable = true;
        remote = "backblaze-b2:company-archive";
        localWriteDir = "/var/lib/workspaces/local-changes";
        localPolicy = "epff";      # Existing path first found
        remotePolicy = "ro";        # Cloud layer remains read-only
        minFreeSpace = "20G";       # Guard local root filesystem
      };
    };
  };

  # Offload sync task: runs nightly to merge local changes upstream
  systemd.services."sync-workspace-to-cloud" = {
    description = "Sync local overlay changes back to Backblaze";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ''
        ${pkgs.rclone}/bin/rclone sync \
          /var/lib/workspaces/local-changes \
          backblaze-b2:company-archive \
          --config=/run/agenix/rclone.conf \
          --fast-list
      '';
    };
  };

  systemd.timers."sync-workspace-to-cloud" = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "03:00 UTC";
      Persistent = true;
    };
  };
}

```

---

## 3. S3 / Cloudflare R2 Mount with Secret Environment Variables

When remotes are configured purely via environment variables rather than a static `rclone.conf`, use `environmentFile` pointing to an encrypted file containing S3 keys.

```bash
# /var/lib/secrets/s3-storage.env (Mode 0400)
RCLONE_CONFIG_S3REMOTE_TYPE=s3
RCLONE_CONFIG_S3REMOTE_PROVIDER=Cloudflare
RCLONE_CONFIG_S3REMOTE_ACCESS_KEY_ID=cf_access_key_12345
RCLONE_CONFIG_S3REMOTE_SECRET_ACCESS_KEY=cf_secret_key_67890
RCLONE_CONFIG_S3REMOTE_ENDPOINT=[https://your-account-id.r2.cloudflarestorage.com](https://your-account-id.r2.cloudflarestorage.com)

```

```nix
# /etc/nixos/modules/s3-mount.nix
{ config, pkgs, ... }:

{
  services.rclone = {
    enable = true;

    mounts."object-data" = {
      remote = "S3REMOTE:my-bucket";
      mountPoint = "/mnt/bucket";
      allowOther = true;
      vfsCacheMode = "full";
      vfsCacheMaxSize = "50G";

      # Injected via EnvironmentFile into the mount's systemd unit
      environmentFile = "/var/lib/secrets/s3-storage.env";

      extraArgs = [
        "--no-checksum"
        "--no-modtime"
      ];
    };
  };
}

```

---

## 4. Automated Cache Pre-Warming via Systemd Timers

When `dirCacheTime` is high (e.g., 7 days), the initial directory scan on reboot or remount can feel sluggish. This recipe wires an automated warmer that uses Rclone's RC API to traverse directories and prime the cache immediately upon start.

```nix
# /etc/nixos/modules/cache-warmer.nix
{ config, pkgs, ... }:

{
  services.rclone = {
    enable = true;
    globalConfigFile = "/run/agenix/rclone.conf";

    mounts."shared-drive" = {
      remote = "gdrive:/Shared";
      mountPoint = "/mnt/shared";
      allowOther = true;
      dirCacheTime = "1000h";

      rc = {
        enable = true;
        address = "127.0.0.1:5575";
        noAuth = true;
      };
    };
  };

  # Cache priming service triggered after the mount is established
  systemd.services."warm-rclone-cache" = {
    description = "Prime Rclone VFS directory cache";
    after = [ "rclone-mount-shared-drive.service" ];
    requires = [ "rclone-mount-shared-drive.service" ];
    wantedBy = [ "rclone-mount-shared-drive.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
      ExecStart = pkgs.writeShellScript "warm-cache" ''
        set -euo pipefail

        echo "Waiting for RC engine to respond..."
        until ${pkgs.curl}/bin/curl -sf [http://127.0.0.1:5575/core/version](http://127.0.0.1:5575/core/version) > /dev/null; do
          sleep 1
        done

        echo "Priming VFS Directory Cache via RC..."
        ${pkgs.curl}/bin/curl -s -X POST \
          [http://127.0.0.1:5575/vfs/refresh](http://127.0.0.1:5575/vfs/refresh) \
          -H "Content-Type: application/json" \
          -d '{"recursive": true}'

        echo "Cache primed successfully."
      '';
    };
  };
}

```
