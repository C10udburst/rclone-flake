# lib/default.nix
{ lib }:

let
  inherit (lib)
    concatStringsSep
    filter
    isString
    mapAttrsToList
    optional
    optionalAttrs
    optionalString
    ;
in
{
  # Transforms typed mount options into CLI flag strings
  buildMountArgs =
    mountCfg:
    let
      boolFlag = flag: cond: optional cond flag;
      strFlag = flag: val: optional (val != null && val != "") "--${flag}=${toString val}";
      intFlag = flag: val: optional (val != null) "--${flag}=${toString val}";

      flags =
        # FUSE / Permissions
        (boolFlag "--allow-other" mountCfg.allowOther)
        ++ (boolFlag "--allow-non-empty" mountCfg.allowNonEmpty)
        ++ (boolFlag "--read-only" mountCfg.readOnly)
        ++ (boolFlag "--default-permissions" mountCfg.defaultPermissions)
        ++ (strFlag "umask" mountCfg.umask)
        ++ (intFlag "uid" mountCfg.uid)
        ++ (intFlag "gid" mountCfg.gid)

        # VFS Cache Tuning
        ++ (strFlag "vfs-cache-mode" mountCfg.vfsCacheMode)
        ++ (strFlag "vfs-cache-max-age" mountCfg.vfsCacheMaxAge)
        ++ (strFlag "vfs-cache-max-size" mountCfg.vfsCacheMaxSize)
        ++ (strFlag "vfs-cache-poll-interval" mountCfg.vfsCachePollInterval)
        ++ (strFlag "vfs-read-chunk-size" mountCfg.vfsReadChunkSize)
        ++ (strFlag "vfs-read-chunk-size-limit" mountCfg.vfsReadChunkSizeLimit)
        ++ (strFlag "vfs-write-back" mountCfg.vfsWriteBack)
        ++ (strFlag "vfs-read-ahead" mountCfg.vfsReadAhead)

        # Directory & Metadata Cache Tuning
        ++ (strFlag "dir-cache-time" mountCfg.dirCacheTime)
        ++ (strFlag "poll-interval" mountCfg.pollInterval)
        ++ (strFlag "attr-timeout" mountCfg.attrTimeout)
        ++ (strFlag "buffer-size" mountCfg.bufferSize)

        # Performance, Transfers & Network
        ++ (strFlag "bwlimit" mountCfg.bwlimit)
        ++ (intFlag "transfers" mountCfg.transfers)
        ++ (intFlag "checkers" mountCfg.checkers)
        ++ (intFlag "low-level-retries" mountCfg.lowLevelRetries)

        # Logging
        ++ (strFlag "log-level" mountCfg.logLevel)
        ++ (strFlag "log-file" mountCfg.logFile)

        # Remote Control (rc)
        ++ (boolFlag "--rc" mountCfg.rc.enable)
        ++ (optional mountCfg.rc.enable "--rc-addr=${mountCfg.rc.address}")
        ++ (boolFlag "--rc-no-auth" (mountCfg.rc.enable && mountCfg.rc.noAuth))

        # Raw user arguments escape hatch
        ++ mountCfg.extraArgs;
    in
    flags;

  # Builds an INI configuration block for an Rclone union overlay
  generateUnionSection =
    name: unionCfg:
    let
      sectionName = "${name}-union";
      quoteIfNeeded = s: if lib.hasInfix " " s then ''"${s}"'' else s;
      localUpstream = quoteIfNeeded "${unionCfg.localWriteDir}:${unionCfg.localPolicy}";
      remoteUpstream = quoteIfNeeded "${unionCfg.remote}:${unionCfg.remotePolicy}";
      upstreams = "${localUpstream} ${remoteUpstream}";

      attrs = {
        type = "union";
        upstreams = upstreams;
      }
      // (optionalAttrs (unionCfg.actionPolicy != null) { action_policy = unionCfg.actionPolicy; })
      // (optionalAttrs (unionCfg.createPolicy != null) { create_policy = unionCfg.createPolicy; })
      // (optionalAttrs (unionCfg.searchPolicy != null) { search_policy = unionCfg.searchPolicy; })
      // (optionalAttrs (unionCfg.minFreeSpace != null) { min_free_space = unionCfg.minFreeSpace; })
      // unionCfg.extraConfig;

      lines = mapAttrsToList (k: v: "${k} = ${v}") attrs;
    in
    "[${sectionName}]\n" + (concatStringsSep "\n" lines) + "\n";
}
