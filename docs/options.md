# Option Reference

This document covers all options available under the `services.rclone` namespace.

---

## Top-Level Options (`services.rclone`)

| Option                                  | Type                   | Default       | Description                                                             |
| :-------------------------------------- | :--------------------- | :------------ | :---------------------------------------------------------------------- |
| `services.rclone.enable`                | `boolean`              | `false`       | Enable the declarative rclone mount management framework.               |
| `services.rclone.package`               | `package`              | `pkgs.rclone` | The package used across all systemd mount units.                        |
| `services.rclone.globalConfigFile`      | `nullOr (path \| str)` | `null`        | Global path to an external `rclone.conf` (e.g. Agenix/sops-nix output). |
| `services.rclone.globalEnvironmentFile` | `nullOr (path \| str)` | `null`        | Global path to an environment file providing secrets to all mounts.     |
| `services.rclone.mounts`                | `attrsOf (submodule)`  | `{}`          | Attribute set of declared rclone mounts.                                |

---

## Mount Options (`services.rclone.mounts.<name>`)

### Target & Identification
- **`mountPoint`** (`str`, *mandatory*): Absolute filesystem path where the remote will be mounted.
- **`remote`** (`nullOr str`, default: `null`): Upstream remote identifier (e.g., `gdrive:/media`). Required unless `union.enable = true`.

### Permissions & System Ownership
- **`user`** (`str`, default: `"root"`): User account running the systemd unit and owning the mount point.
- **`group`** (`str`, default: `"root"`): Group account running the systemd unit and owning the mount point.
- **`allowOther`** (`bool`, default: `false`): Enables the `--allow-other` FUSE flag. Activates `programs.fuse.userAllowOther`.
- **`allowNonEmpty`** (`bool`, default: `false`): Enables `--allow-non-empty`.
- **`readOnly`** (`bool`, default: `false`): Mounts the filesystem in read-only mode (`--read-only`).
- **`defaultPermissions`** (`bool`, default: `false`): Enforces kernel-level permission checks (`--default-permissions`).
- **`umask`** (`str`, default: `"022"`): Filesystem umask applied to created nodes.
- **`uid`** (`nullOr int`, default: `null`): Override the user ID presented to the OS.
- **`gid`** (`nullOr int`, default: `null`): Override the group ID presented to the OS.

### VFS Caching Layer
- **`vfsCacheMode`** (`enum [ "off", "minimal", "writes", "full" ]`, default: `"writes"`): Cache policy. Set to `"full"` for random-access workloads (e.g., media streaming).
- **`vfsCacheMaxAge`** (`str`, default: `"24h"`): Maximum duration an inactive file remains in the VFS cache.
- **`vfsCacheMaxSize`** (`str`, default: `"50G"`): Maximum local storage consumed by the cache (e.g. `"10G"`, `"100G"`).
- **`vfsCachePollInterval`** (`str`, default: `"1m"`): How frequently Rclone scans the cache to evict expired items.
- **`vfsReadChunkSize`** (`str`, default: `"128M"`): Initial chunk size requested during sequential reads.
- **`vfsReadChunkSizeLimit`** (`str`, default: `"off"`): Maximum boundary for dynamic chunk sizing expansion.
- **`vfsWriteBack`** (`str`, default: `"5s"`): Time to buffer local modifications before syncing back to upstream cloud storage.
- **`vfsReadAhead`** (`str`, default: `"128M"`): Lookahead buffer for sequential file reads.

### Directory Metadata & Buffers
- **`dirCacheTime`** (`str`, default: `"72h"`): How long directory listings are kept in memory.
- **`pollInterval`** (`str`, default: `"1m"`): Frequency to poll remotes supporting change notifications (Google Drive, OneDrive).
- **`attrTimeout`** (`str`, default: `"1s"`): Kernel attribute cache duration.
- **`bufferSize`** (`str`, default: `"16M"`): Per-file in-memory read buffer.

### Network, Concurrency & Bandwidth
- **`bwlimit`** (`nullOr str`, default: `null`): Bandwidth ceiling (e.g., `"10M"`, `"20M:50M"`).
- **`transfers`** (`nullOr int`, default: `null`): Maximum concurrent file transfers.
- **`checkers`** (`nullOr int`, default: `null`): Maximum concurrent metadata verification routines.
- **`lowLevelRetries`** (`nullOr int`, default: `null`): Maximum low-level retry attempts before reporting an I/O failure.

### Secrets & Environment
- **`configFile`** (`nullOr (path | str)`, default: `null`): Mount-specific override for `rclone.conf`.
- **`environmentFile`** (`nullOr (path | str)`, default: `null`): Systemd `EnvironmentFile` containing tokens for this unit.
- **`environment`** (`attrsOf str`, default: `{}`): Inline environment variables exported to the service.

### Remote Control (RC) (`services.rclone.mounts.<name>.rc`)
- **`rc.enable`** (`bool`, default: `false`): Starts the internal HTTP engine for Rclone remote control.
- **`rc.address`** (`str`, default: `"127.0.0.1:5572"`): Binding address and port for the RC server.
- **`rc.noAuth`** (`bool`, default: `false`): Disables authentication requirements on the RC interface.

### Union Overlays (`services.rclone.mounts.<name>.union`)
- **`union.enable`** (`bool`, default: `false`): Enables a local-write overlay using the Rclone `union` backend.
- **`union.remote`** (`nullOr str`, default: `null`): Cloud backend upstream acting as the read base layer.
- **`union.localWriteDir`** (`str`, default: `"/var/lib/rclone/local-layers/${name}"`): Local path receiving writes and creations.
- **`union.localPolicy`** (`str`, default: `"epff"`): Search/write policy for the local layer.
- **`union.remotePolicy`** (`str`, default: `"ro"`): Search/write policy for the cloud remote.
- **`union.actionPolicy`** (`nullOr str`, default: `null`): Policy applied to file actions (`"all"`, `"epall"`).
- **`union.createPolicy`** (`nullOr str`, default: `null`): Policy applied to file creation (`"epff"`, `"mfs"`).
- **`union.searchPolicy`** (`nullOr str`, default: `null`): Policy applied to search resolution.
- **`union.minFreeSpace`** (`nullOr str`, default: `null`): Minimum local free space required before blocking writes (e.g. `"10G"`).
- **`union.extraConfig`** (`attrsOf str`, default: `{}`): Additional configuration keys for the generated INI section.

### Escape Hatch
- **`extraArgs`** (`listOf str`, default: `[]`): Unchecked list of CLI arguments appended directly to `rclone mount`.
