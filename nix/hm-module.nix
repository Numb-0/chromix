self: {
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption mkEnableOption mkIf mkDefault mkMerge types;

  cfg = config.programs.chromix;

  # Where the CLI keeps the selection and the `current` link. Apps are
  # pointed through current/ with out-of-store symlinks, so a switch
  # never needs a rebuild.
  stateDir = "${config.xdg.stateHome}/chromix";
  current = "${stateDir}/current";
  link = file: config.lib.file.mkOutOfStoreSymlink "${current}/${file}";

  schemeTypes = [
    "scheme-content"
    "scheme-expressive"
    "scheme-fidelity"
    "scheme-fruit-salad"
    "scheme-monochrome"
    "scheme-neutral"
    "scheme-rainbow"
    "scheme-tonal-spot"
    "scheme-vibrant"
  ];

  schemeOptions = {
    type = mkOption {
      type = types.enum schemeTypes;
      default = "scheme-tonal-spot";
      description = "The Material 3 scheme variant matugen generates.";
    };

    contrast = mkOption {
      type = types.numbers.between (-1) 1;
      default = 0;
      description = "Contrast from -1 (lowest) through 0 (as specified) to 1 (highest).";
    };
  };

  themeModule = types.submodule {
    options =
      {
        color = mkOption {
          type = types.nullOr (types.strMatching "#[0-9a-fA-F]{6}");
          default = null;
          example = "#1e88e5";
          description = "Seed colour to generate the theme from.";
        };

        image = mkOption {
          type = types.nullOr types.path;
          default = null;
          example = lib.literalExpression "./walls/forest.jpg";
          description = "Image to take the seed colour from. Copied into the store.";
        };
      }
      // schemeOptions;
  };

  targetModule = types.submodule {
    options = {
      enable = mkEnableOption "this target";

      template = mkOption {
        type = types.path;
        description = "matugen template rendered for every theme.";
      };

      output = mkOption {
        type = types.str;
        example = "kitty/colors.conf";
        description = "Where the rendered file lands inside a theme directory.";
      };

      reload = mkOption {
        type = types.lines;
        default = "";
        description = ''
          Shell run after every switch to make a running app pick the
          new theme up. $CHROMIX_MODE, $CHROMIX_THEME and
          $CHROMIX_CURRENT are set. Failures are reported and ignored.
        '';
      };
    };
  };

  # A built-in target follows its app's Home Manager module: on by
  # default with it, and never rendered or linked without it, even if
  # enabled. Your own targets have no module to wait on.
  programEnabled = {
    morph-shell = config.programs.morph-shell.enable or false;
    kitty = config.programs.kitty.enable;
    hyprland = hyprland.enable;
    gtk = config.gtk.enable;
    neovim = config.programs.neovim.enable;
  };

  enabledTargets = lib.filterAttrs (name: t: t.enable && (programEnabled.${name} or true)) cfg.targets;
  active = name: enabledTargets ? ${name};

  generator = {
    inherit (cfg.wallpaper) type contrast;
    customColors = cfg.customColors;
    targets =
      lib.mapAttrsToList (name: t: {
        inherit name;
        template = "${t.template}";
        inherit (t) output;
      })
      enabledTargets;
  };

  buildTheme = pkgs.callPackage ./build-theme.nix {chromix = cfg.package;};

  themes =
    lib.mapAttrs (name: theme: let
      source =
        if theme.color != null
        then {inherit (theme) color;}
        else {image = "${theme.image}";};
      build = mode:
        buildTheme {
          inherit name mode source;
          generator = generator // {inherit (theme) type contrast;};
        };
    in {
      dark = build "dark";
      light = build "light";
    })
    cfg.themes;

  reloadScript = pkgs.writeShellScript "chromix-reload" (lib.concatStrings (lib.mapAttrsToList (name: t:
    lib.optionalString (t.reload != "") ''
      (
      ${t.reload}
      ) || echo "chromix: reloading ${name} failed" >&2
    '')
  enabledTargets));

  manifest = pkgs.writeText "chromix-manifest.json" (builtins.toJSON {
    inherit (cfg) default;
    inherit generator themes;
    reload = reloadScript;
  });

  hyprland = config.wayland.windowManager.hyprland;
  hyprlandLua = (hyprland.configType or "hyprlang") == "lua";
in {
  options.programs.chromix = {
    enable = mkEnableOption "chromix, a runtime theme switcher built on matugen";

    package = mkOption {
      type = types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.chromix;
      description = "The chromix package to use.";
    };

    themes = mkOption {
      type = types.attrsOf themeModule;
      default = {};
      example = lib.literalExpression ''
        {
          ocean.color = "#1e88e5";
          forest = { image = ./walls/forest.jpg; type = "scheme-expressive"; };
        }
      '';
      description = "Themes to build ahead of time, each in a dark and a light mode.";
    };

    default = {
      theme = mkOption {
        type = types.str;
        description = "Theme applied the first time, before anything has been picked.";
      };

      mode = mkOption {
        type = types.enum ["dark" "light"];
        default = "dark";
        description = "Mode applied the first time.";
      };
    };

    wallpaper = schemeOptions;

    customColors = mkOption {
      type = types.attrsOf (types.strMatching "#[0-9a-fA-F]{6}");
      description = ''
        Extra colours matugen generates alongside the scheme, each
        harmonised towards the seed with on-, container and
        on-container tones. The built-in templates need red, green,
        yellow, blue, magenta and cyan (terminal colours) and success
        and warning (states Material has no role for); set a key to
        change its hue.
      '';
    };

    targets = mkOption {
      type = types.attrsOf targetModule;
      default = {};
      description = ''
        Apps to theme. A built-in target is on while its app's Home
        Manager module is, unless you turn it off, and never without
        it; add your own with a template and an output.
      '';
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions =
        [
          {
            assertion = cfg.themes ? ${cfg.default.theme};
            message = "programs.chromix.default.theme: '${cfg.default.theme}' is not in programs.chromix.themes.";
          }
          {
            assertion = !(cfg.themes ? wallpaper);
            message = "programs.chromix.themes: 'wallpaper' is reserved for themes made with `chromix wall`.";
          }
        ]
        ++ lib.mapAttrsToList (name: t: {
          assertion = (t.color == null) != (t.image == null);
          message = "programs.chromix.themes.${name}: set exactly one of color and image.";
        })
        cfg.themes;

      home.packages = [cfg.package];
      xdg.configFile."chromix/manifest.json".source = manifest;

      # Moves current to the rebuilt store paths while keeping whatever
      # was picked at runtime, and makes the first link on a fresh
      # install. Apps are not poked here: activation can run outside the
      # graphical session.
      home.activation.chromix = lib.hm.dag.entryAfter ["writeBoundary"] ''
        CHROMIX_MANIFEST=${manifest} run ${lib.getExe cfg.package} refresh --no-reload
      '';

      programs.chromix.customColors = lib.mapAttrs (_: mkDefault) {
        red = "#e5484d";
        green = "#46a758";
        yellow = "#e2a336";
        blue = "#3e8ef7";
        magenta = "#b659d8";
        cyan = "#12a5b0";
        success = "#46a758";
        warning = "#e2a336";
      };

      programs.chromix.targets = {
        morph-shell = {
          enable = mkDefault programEnabled.morph-shell;
          template = mkDefault ../templates/morph-shell.json;
          output = mkDefault "morph-shell/colors.json";
          # Required: the shell watches its colours file, but the watch
          # does not see current/ being repointed further up the chain.
          reload = mkDefault ''
            if command -v morph-shell >/dev/null; then
              morph-shell ipc call palette reload >/dev/null
            fi
          '';
        };

        kitty = {
          enable = mkDefault programEnabled.kitty;
          template = mkDefault ../templates/kitty.conf;
          output = mkDefault "kitty/colors.conf";
          reload = mkDefault ''
            ${pkgs.procps}/bin/pkill -USR1 -x kitty || true
          '';
        };

        hyprland = {
          enable = mkDefault programEnabled.hyprland;
          template = mkDefault (
            if hyprlandLua
            then ../templates/hyprland.lua
            else ../templates/hyprland.conf
          );
          output = mkDefault (
            if hyprlandLua
            then "hyprland/colors.lua"
            else "hyprland/colors.conf"
          );
          reload = mkDefault ''
            if [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v hyprctl >/dev/null; then
              hyprctl reload >/dev/null
            fi
          '';
        };

        gtk = {
          enable = mkDefault programEnabled.gtk;
          template = mkDefault ../templates/gtk.css;
          output = mkDefault "gtk/gtk.css";
          # Running GTK apps do not reread gtk.css, but libadwaita ones
          # follow the colour scheme live. dconf rather than gsettings,
          # which needs the schemas on its path to write anything.
          reload = mkDefault ''
            ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/color-scheme "'prefer-$CHROMIX_MODE'"
          '';
        };

        neovim = {
          enable = mkDefault programEnabled.neovim;
          template = mkDefault ../templates/nvim.lua;
          output = mkDefault "nvim/colors.lua";
          reload = mkDefault ''
            if command -v nvim >/dev/null; then
              for server in "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/nvim.*.0; do
                [ -S "$server" ] || continue
                nvim --server "$server" --remote-expr "execute('luafile $CHROMIX_CURRENT/nvim/colors.lua')" >/dev/null || true
              done
            fi
          '';
        };
      };
    }

    (mkIf (active "morph-shell") {
      xdg.stateFile."morph-shell/colors.json".source = link cfg.targets.morph-shell.output;
    })

    (mkIf (active "kitty") {
      programs.kitty.extraConfig = ''
        include ${current}/${cfg.targets.kitty.output}
      '';
    })

    (mkIf (active "hyprland") {
      wayland.windowManager.hyprland.extraConfig =
        if hyprlandLua
        then ''
          pcall(dofile, "${current}/${cfg.targets.hyprland.output}")
        ''
        else ''
          source = ${current}/${cfg.targets.hyprland.output}
        '';
    })

    # The gtk module owns gtk.css, so import from there.
    (mkIf (active "gtk") {
      gtk.gtk3.extraCss = ''@import url("file://${current}/${cfg.targets.gtk.output}");'';
      gtk.gtk4.extraCss = ''@import url("file://${current}/${cfg.targets.gtk.output}");'';
    })

    (mkIf (active "neovim") {
      programs.neovim.plugins = [pkgs.vimPlugins.mini-base16];
      programs.neovim.extraLuaConfig = ''
        pcall(dofile, "${current}/${cfg.targets.neovim.output}")
      '';
    })
  ]);
}
