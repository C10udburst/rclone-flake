# Architecture & Technical Design

This document details the internal mechanisms of the `services.rclone` NixOS module, focusing on runtime isolation, FUSE integration, and dynamic configuration generation.

## System Overview


```
                  +---------------------------------------+
                  |       NixOS Evaluation Stage         |
                  +---------------------------------------+
                                      |
            +-------------------------+-------------------------+
            |                                                   |
  [ options.nix / default.nix ]                      [ config.nix ]
  - Submodule validation                             - Generates Union INI blocks
  - Type assertions                                  - Exports to Nix Store:
  - tmpfiles.rules definitions                         /etc/rclone/rclone-generated.conf
            |                                                   |
            +-------------------------+-------------------------+
                                      |
                                      v
                  +---------------------------------------+
                  |         Systemd Service Setup         |
                  |      (rclone-mount-${name}.service)   |
                  +---------------------------------------+
                                      |
                                      | 1. tmpfiles ensures mount points exist
                                      | 2. RuntimeDirectory creates /run/rclone-${name} (0700)
                                      v
                  +---------------------------------------+
                  |     ExecStartPre (prepareConfig)      |
                  +---------------------------------------+
                                      |
    Reads /run/agenix/rclone.conf ----+
    (Decrypted Secrets, unprivileged) |
                                      +--> Concatenates into /run/rclone-${name}/rclone.conf (0600)
    Reads /etc/rclone/rclone-gen.conf +
    (Nix-managed union definitions)   |
                                      v
                  +---------------------------------------+
                  |         ExecStart (rclone mount)      |
                  |   - Uses ephemeral /run config        |
                  |   - Sends sd_notify handshake         |
                  |   - Uses /run/wrappers for FUSE       |
                  +---------------------------------------+

```

---

## 1. Secret Protection & Ephemeral Config Synthesis

### The Problem
Rclone configuration files typically contain cleartext OAuth tokens, API refresh credentials, or symmetric encryption keys. Declaring these endpoints directly in Nix derivations or placing them into the `/etc` closure causes credentials to be copied to the world-readable `/nix/store`.

### The Solution
The module keeps Nix declarative generation and runtime secrets strictly decoupled:

1. **Static Union Structures:** Definitions containing no secrets (e.g., local union overlay structures) are compiled into `/etc/rclone/rclone-generated.conf` via `environment.etc`.
2. **Secret Inputs:** Credentials remain within external secret mechanisms (`config.globalConfigFile` pointing to Agenix, sops-nix, or a manual location).
3. **Runtime Assembly (`ExecStartPre`):** Before each mount starts, an ephemeral shell script runs within the unit's context:
   - Sets up `/run/rclone-${name}/rclone.conf` inside a private runtime directory (`RuntimeDirectory = "rclone-${name}"`, permissions `0700`).
   - Merges the external secret file with the generated union configurations.
   - Enforces `chmod 600` on the combined configuration file.
   - Once the service stops or crashes, systemd cleans up the `RuntimeDirectory` automatically.

---

## 2. NixOS FUSE Wrapper Integration

Mounting through FUSE on NixOS requires handling two system-specific requirements:

1. **`user_allow_other`:** In standard Linux systems, FUSE disables the `allow_other` option unless `/etc/fuse.conf` explicitly contains `user_allow_other`. The module inspects every mount defined under `services.rclone.mounts`:
```nix
   programs.fuse.userAllowOther = any (m: m.allowOther) (attrValues cfg.mounts);
```

2. **Setuid Wrappers (`fusermount3`):** Unprivileged users and system daemons require the setuid wrapper for `fusermount3`, which lives in `/run/wrappers/bin`. The module enforces this across all services:
```nix
path = [ cfg.package pkgs.fuse3 pkgs.coreutils "/run/wrappers" ];
environment.PATH = "/run/wrappers/bin:/run/current-system/sw/bin";
```



---

## 3. Directory Creation via `tmpfiles.d`

If an `rclone mount` starts before its local target directory or local write layer exists, initialization fails. Rather than running `mkdir -p` inline during service execution, the module uses declarative systemd tmpfiles:

```nix
systemd.tmpfiles.rules = flatten (
  mapAttrsToList (name: m: [
    "d ${m.mountPoint} 0755 ${m.user} ${m.group} -"
  ] ++ optional m.union.enable "d ${m.union.localWriteDir} 0755 ${m.user} ${m.group} -") cfg.mounts
);

```

This guarantees correct permissions and ownership (`m.user`, `m.group`) on system activation before any target services reach the start queue.

---

## 4. Lifecycle & Systemd Handshakes

* **`Type = "notify"`:** Rclone natively supports the systemd notify protocol. It calls `sd_notify("READY=1")` only after the FUSE mount has mounted and established communication with the upstream remote. Dependent services (`wants = [ "rclone-mount-media.service" ]`) can safely rely on paths being available as soon as the service reaches `active`.
* **Clean Teardown:** Systemd unmounts cleanly using `ExecStop = "${pkgs.coreutils}/bin/umount ${m.mountPoint}";` with `KillMode = "mixed"` to prevent hanging processes from locking FUSE mount nodes.
