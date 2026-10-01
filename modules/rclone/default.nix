# modules/rclone/default.nix
{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    hasPrefix
    mapAttrsToList
    ;

  cfg = config.services.rclone;

in
{
  imports = [
    ./options.nix
    ./config.nix
    ./systemd.nix
  ];

  config = lib.mkIf cfg.enable {
    # Evaluation-time assertions for safety
    assertions = lib.flatten (
      mapAttrsToList (name: m: [
        {
          assertion = m.union.enable || (m.remote != null);
          message = "services.rclone.mounts.${name}: either 'remote' or 'union.enable' must be set.";
        }
        {
          assertion = !m.union.enable || (m.union.remote != null);
          message = "services.rclone.mounts.${name}.union: 'union.remote' is required when union is enabled.";
        }
        {
          assertion = hasPrefix "/" m.mountPoint;
          message = "services.rclone.mounts.${name}: 'mountPoint' must be an absolute path (starts with '/').";
        }
        {
          assertion = !m.union.enable || (hasPrefix "/" m.union.localWriteDir);
          message = "services.rclone.mounts.${name}.union: 'localWriteDir' must be an absolute path.";
        }
      ]) cfg.mounts
    );
  };
}
