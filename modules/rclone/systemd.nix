# modules/rclone/systemd.nix
{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    any
    attrValues
    escapeShellArgs
    flatten
    mapAttrs'
    mapAttrsToList
    nameValuePair
    optional
    optionalString
    ;

  cfg = config.services.rclone;
  rcloneLib = import ../../lib { inherit lib; };

  # Factory for generating systemd service per mount
  mkMountService =
    name: m:
    let
      targetRemote = if m.union.enable then "${name}-union:" else m.remote;
      mountFlags = rcloneLib.buildMountArgs m;

      # Effective static or secret config source
      effectiveBaseConfig =
        if m.configFile != null then
          m.configFile
        else if cfg.globalConfigFile != null then
          cfg.globalConfigFile
        else
          "";

      # Script running in ExecStartPre to merge secrets and generated unions
      prepareConfigScript = pkgs.writeShellScript "prepare-rclone-${name}-conf" ''
        set -euo pipefail

        BASE_CONF="${effectiveBaseConfig}"
        GEN_CONF="/etc/rclone/rclone-generated.conf"
        TARGET_CONF="/run/rclone-${name}/rclone.conf"

        mkdir -p "${m.mountPoint}"
        ${optionalString m.union.enable ''mkdir -p "${m.union.localWriteDir}"''}

        : > "$TARGET_CONF"

        # 1. Safely append global or mount-specific config file (e.g. Agenix secret)
        if [ -n "$BASE_CONF" ] && [ -f "$BASE_CONF" ]; then
          cat "$BASE_CONF" >> "$TARGET_CONF"
        elif [ -z "$BASE_CONF" ]; then
          if [ -f "/var/lib/rclone/rclone.conf" ]; then
            cat "/var/lib/rclone/rclone.conf" >> "$TARGET_CONF"
          elif [ -f "/root/.config/rclone/rclone.conf" ]; then
            cat "/root/.config/rclone/rclone.conf" >> "$TARGET_CONF"
          elif [ -f "/etc/rclone/rclone.conf" ]; then
            cat "/etc/rclone/rclone.conf" >> "$TARGET_CONF"
          fi
        fi

        # 2. Append internal generated declarative remotes (unions)
        if [ -f "$GEN_CONF" ]; then
          cat "$GEN_CONF" >> "$TARGET_CONF"
        fi

        chown ${m.user}:${m.group} "$TARGET_CONF" || true
        chmod 600 "$TARGET_CONF"
      '';

      stopMountScript = pkgs.writeShellScript "stop-rclone-${name}" ''
        if [ -x /run/wrappers/bin/fusermount3 ]; then
          /run/wrappers/bin/fusermount3 -u -z "${m.mountPoint}" || true
        elif command -v fusermount3 >/dev/null 2>&1; then
          fusermount3 -u -z "${m.mountPoint}" || true
        else
          ${pkgs.coreutils}/bin/umount -l "${m.mountPoint}" || true
        fi
      '';

    in
    nameValuePair "rclone-mount-${name}" {
      description = "Rclone Mount Service for ${name} (${m.mountPoint})";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      # Ensure fusermount3 wrapper and core utilities are found on NixOS
      path = [
        cfg.package
        pkgs.fuse3
        pkgs.coreutils
        "/run/wrappers"
      ];

      environment = m.environment;

      serviceConfig = {
        Type = "notify";
        Restart = "on-failure";
        RestartSec = "5s";
        TimeoutStartSec = "60s";
        TimeoutStopSec = "20s";
        KillMode = "mixed";

        User = m.user;
        Group = m.group;

        # Automatically manages /run/rclone-${name} with 0700 permissions
        RuntimeDirectory = "rclone-${name}";
        RuntimeDirectoryMode = "0700";

        EnvironmentFile =
          optional (cfg.globalEnvironmentFile != null) cfg.globalEnvironmentFile
          ++ optional (m.environmentFile != null) m.environmentFile;

        ExecStartPre = [
          "+${prepareConfigScript}"
        ];

        ExecStart = ''
          ${cfg.package}/bin/rclone mount ${targetRemote} ${m.mountPoint} \
            --config=/run/rclone-${name}/rclone.conf \
            ${escapeShellArgs mountFlags}
        '';

        ExecStop = "${stopMountScript}";
      };
    };

in
{
  config = lib.mkIf cfg.enable {
    # 1. Automatically enable userAllowOther in FUSE if any mount requests it
    programs.fuse.userAllowOther = any (m: m.allowOther) (attrValues cfg.mounts);

    # 2. Ensure mount points and local union write layers exist before mounting
    systemd.tmpfiles.rules = flatten (
      [
        "d /var/lib/rclone 0750 root root -"
      ]
      ++ mapAttrsToList (
        name: m:
        [
          "d ${m.mountPoint} 0755 ${m.user} ${m.group} -"
        ]
        ++ optional m.union.enable "d ${m.union.localWriteDir} 0755 ${m.user} ${m.group} -"
      ) cfg.mounts
    );

    # 3. Generate systemd services for all defined mounts
    systemd.services = mapAttrs' mkMountService cfg.mounts;
  };
}
