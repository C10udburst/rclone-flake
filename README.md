# rclone-nixos

A scalable, declarative NixOS Flake module for managing production-grade [Rclone](https://rclone.org/) mounts.

Unlike ad-hoc systemd units, this module provides an evaluation-checked option interface under `services.rclone`, handling FUSE wrappers, directory creation via `tmpfiles.d`, runtime secret protection (Agenix/sops-nix), and dynamic INI configuration synthesis (such as read-only cloud remotes overlaid with local-write union layers).

---

## Features

* **Declarative Mount Submodules:** Type-checked configuration options covering VFS caching, attribute timeouts, buffer allocations, bandwidth caps, and FUSE permissions.
* **Local-Write Overlay (Union Mounts):** Built-in synthesis of Rclone `union` remotes to overlay read-only cloud backends with local writable directories without modifying external config files.
* **Leak-Free Secret Management:** Merges static or runtime secrets (such as Agenix/sops-nix managed tokens) in `ExecStartPre` into ephemeral, non-world-readable `/run` paths (`0600`)—never embedding API credentials into the `/nix/store`.
* **NixOS FUSE Integration:** Automatically sets `programs.fuse.userAllowOther = true;` when needed and resolves `fusermount3` via `/run/wrappers/bin`.
* **Systemd Lifecycle Management:** Proper notify-type systemd integration (`Type = "notify"`), network targets (`network-online.target`), graceful unmounting via `ExecStop`, and automated pre-creation of local directories.

---

## Quick Start

### 1. Add Flake Input

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    rclone-nixos.url = "github:your-org/rclone-nixos";
  };

  outputs = { self, nixpkgs, rclone-nixos, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        rclone-nixos.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}

```

### 2. Configure Mounts

```nix
# configuration.nix
{ config, pkgs, ... }:

{
  services.rclone = {
    enable = true;

    # Global decrypted credentials file (e.g. managed by Agenix or sops-nix)
    globalConfigFile = "/run/agenix/rclone.conf";

    mounts = {
      # Standard Cloud Mount
      "media" = {
        remote = "google-drive:/media";
        mountPoint = "/mnt/media";
        vfsCacheMode = "full";
        vfsCacheMaxSize = "100G";
        dirCacheTime = "72h";
        allowOther = true;
      };

      # Cloud Read Channel + Local Write Layer (Union)
      "secure-backup" = {
        mountPoint = "/mnt/secure-backup";
        vfsCacheMode = "full";
        allowOther = true;
        union = {
          enable = true;
          remote = "dropbox:/backups";
          # Writes persist to: /var/lib/rclone/local-layers/secure-backup
        };
      };
    };
  };
}

```

---

## Documentation

* [Architecture & Internals](docs/architecture.md) — How dynamic configuration generation, secret handling, and systemd sandboxing operate.
* [Option Reference](docs/options.md) — Complete list of module options and their evaluation defaults.
* [Production Recipes](docs/recipes.md) — Real-world configurations for Plex/Jellyfin, S3/MinIO, backup sync overlays, and cache-warming timers.
