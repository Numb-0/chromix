# The system half of the chromium-policy target: Chromium reads policies
# only from /etc, so the policy file one user's chromix renders is linked
# there, through current/, so a switch needs no rebuild.
{
  config,
  lib,
  ...
}: let
  cfg = config.programs.chromix;
in {
  options.programs.chromix.chromiumPolicy = {
    user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "alice";
      description = ''
        The user whose chromix theme colours Chromium for everyone on
        this machine, through the BrowserThemeColor policy rendered by
        their chromium-policy target. That user's XDG_STATE_HOME must
        be the default, ~/.local/state.
      '';
    };
  };

  config = lib.mkIf (cfg.chromiumPolicy.user != null) {
    environment.etc."chromium/policies/managed/chromix.json".source = "${config.users.users.${cfg.chromiumPolicy.user}.home}/.local/state/chromix/current/chromium/policy.json";
  };
}
