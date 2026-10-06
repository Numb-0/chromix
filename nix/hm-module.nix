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

        colorIndex = mkOption {
          type = types.ints.unsigned;
          default = 0;
          description = ''
            Which of the colours matugen extracts from image to seed the
            theme with, most prominent first. Only used with image.
          '';
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
  # default with it, and only wired into that module when it is on.
  # Enabled without it, the file is still rendered, for an app you
  # configure yourself. Your own targets have no module to wait on.
  programEnabled = {
    morph-shell = config.programs.morph-shell.enable or false;
    kitty = config.programs.kitty.enable;
    hyprland = hyprland.enable;
    gtk = config.gtk.enable;
    neovim = config.programs.neovim.enable;
    btop = config.programs.btop.enable;
    hyprlock = config.programs.hyprlock.enable;
    yazi = config.programs.yazi.enable;
    yazi-syntax = config.programs.yazi.enable;
    qt = config.qt.enable && config.qt.platformTheme.name == "qtct";
    fzf = config.programs.fzf.enable;
    eza = config.programs.eza.enable;
    fastfetch = config.programs.fastfetch.enable;
    imv = config.programs.imv.enable;
    vim = config.programs.vim.enable;
    git = config.programs.git.enable;
    vscode = config.programs.vscode.enable;
    firefox = config.programs.firefox.enable;
    thunderbird = config.programs.thunderbird.enable;
    chromium = config.programs.chromium.enable;
    prismlauncher = config.programs.prismlauncher.enable;
    papirus = papirus != null;
  };

  # Wired in without their app's module: their files land in a
  # directory of chromix's own, whoever installed Chromium. They are
  # still only on by default with the module.
  standalone = ["chromium" "chromium-policy"];

  # Halves of another target, on whenever it is.
  companion = {
    firefox-content = "firefox";
    chromium-policy = "chromium";
  };

  enabledTargets = lib.filterAttrs (_: t: t.enable) cfg.targets;
  active = name:
    enabledTargets
    ? ${name}
    && (lib.elem name standalone || (programEnabled.${companion.${name} or name} or true));

  # Papirus from the gtk module, the only place an icon theme is set.
  papirus = let
    icons = config.gtk.iconTheme;
  in
    if config.gtk.enable && icons != null && icons.package != null && lib.getName icons.package == "papirus-icon-theme"
    then "${icons.package}/share/icons"
    else null;

  papirusScript = pkgs.writeShellApplication {
    name = "chromix-papirus";
    runtimeInputs = with pkgs; [coreutils findutils gawk jq];
    text = builtins.readFile ./papirus.sh;
  };
  papirusRun = "${lib.getExe papirusScript} ${papirus} ${cfg.targets.papirus.output}";

  # Firefox and Thunderbird installed outside Home Manager: their
  # stylesheets go into whatever profiles their profiles.ini lists.
  profilesScript = pkgs.writeShellApplication {
    name = "chromix-profiles";
    runtimeInputs = with pkgs; [coreutils gawk];
    text = builtins.readFile ./profiles.sh;
  };
  unmanaged = name: enabledTargets ? ${name} && !programEnabled.${companion.${name} or name};
  stylesheet = file: target: lib.optional (unmanaged target) "${file}=${current}/${cfg.targets.${target}.output}";
  firefoxSheets = stylesheet "userChrome.css" "firefox" ++ stylesheet "userContent.css" "firefox-content";
  thunderbirdSheets = stylesheet "userChrome.css" "thunderbird";
  linkProfiles = root: sheets:
    lib.optionalString (sheets != []) ''
      run ${lib.getExe profilesScript} ${lib.escapeShellArgs ([root] ++ sheets)}
    '';

  # A theme-only VS Code extension. Its theme file points through
  # current/, so the extension itself never changes. The same file is
  # contributed twice so VS Code can pair one with each mode
  # (window.autoDetectColorScheme): it follows the colour scheme the gtk
  # target sets, and rereads the theme whenever that flips.
  vscodeExtension = let
    id = "chromix.chromix-theme";
    manifest = pkgs.writeText "chromix-vscode-package.json" (builtins.toJSON {
      name = "chromix-theme";
      displayName = "Chromix";
      description = "The current chromix theme";
      publisher = "chromix";
      version = "1.0.0";
      engines.vscode = "^1.70.0";
      categories = ["Themes"];
      contributes.themes = [
        {
          label = "Chromix Dark";
          uiTheme = "vs-dark";
          path = "./themes/chromix.json";
        }
        {
          label = "Chromix Light";
          uiTheme = "vs";
          path = "./themes/chromix.json";
        }
      ];
    });
  in
    pkgs.runCommand "chromix-vscode-theme" {
      passthru = {
        vscodeExtUniqueId = id;
        vscodeExtPublisher = "chromix";
        vscodeExtName = "chromix-theme";
        version = "1.0.0";
      };
    } ''
      ext=$out/share/vscode/extensions/${id}
      mkdir -p $ext/themes
      cp ${manifest} $ext/package.json
      ln -s ${current}/${cfg.targets.vscode.output} $ext/themes/chromix.json
    '';

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
        else {
          image = "${theme.image}";
          inherit (theme) colorIndex;
        };
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
        yellow, blue, magenta and cyan (terminal colours), orange (for
        Neovim's base16 palette) and success and warning (states
        Material has no role for); set a key to change its hue.
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
        orange = "#f5700a";
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
            ${pkgs.procps}/bin/pkill -USR1 -x 'kitty|\.kitty-wrapped' || true
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

        # SIGUSR2 makes btop reread its config, and the theme with it.
        btop = {
          enable = mkDefault programEnabled.btop;
          template = mkDefault ../templates/btop.theme;
          output = mkDefault "btop/chromix.theme";
          reload = mkDefault ''
            ${pkgs.procps}/bin/pkill -USR2 -x 'btop|\.btop-wrapped' || true
          '';
        };

        # hyprlock reads its config on every start: nothing to reload.
        hyprlock = {
          enable = mkDefault programEnabled.hyprlock;
          template = mkDefault ../templates/hyprlock.conf;
          output = mkDefault "hyprlock/colors.conf";
        };

        # app:theme rereads theme.toml and the flavor; receiver 0 sends
        # it to every running yazi.
        yazi = {
          enable = mkDefault programEnabled.yazi;
          template = mkDefault ../templates/yazi.toml;
          output = mkDefault "yazi/flavor.toml";
          reload = mkDefault ''
            if command -v ya >/dev/null; then
              ya emit-to 0 app:theme 2>/dev/null || true
            fi
          '';
        };

        # Highlighting for yazi's code previews, from the flavor's
        # tmtheme.xml. Nothing to reload: the yazi target's app:theme
        # rereads the whole flavor.
        yazi-syntax = {
          enable = mkDefault programEnabled.yazi-syntax;
          template = mkDefault ../templates/yazi-tmtheme.xml;
          output = mkDefault "yazi/tmtheme.xml";
        };

        # Qt apps through qt5ct and qt6ct. They read the palette at
        # startup; nothing reloads a running one.
        qt = {
          enable = mkDefault programEnabled.qt;
          template = mkDefault ../templates/qtct.conf;
          output = mkDefault "qt/chromix.conf";
        };

        # The terminal tools below read their file on every run, so a
        # switch shows up on the next one with nothing to reload.
        fzf = {
          enable = mkDefault programEnabled.fzf;
          template = mkDefault ../templates/fzf.txt;
          output = mkDefault "fzf/colors";
        };

        eza = {
          enable = mkDefault programEnabled.eza;
          template = mkDefault ../templates/eza.yml;
          output = mkDefault "eza/theme.yml";
        };

        fastfetch = {
          enable = mkDefault programEnabled.fastfetch;
          template = mkDefault ../templates/fastfetch.jsonc;
          output = mkDefault "fastfetch/config.jsonc";
        };

        git = {
          enable = mkDefault programEnabled.git;
          template = mkDefault ../templates/git.gitconfig;
          output = mkDefault "git/colors.gitconfig";
        };

        # Read when an image is opened.
        imv = {
          enable = mkDefault programEnabled.imv;
          template = mkDefault ../templates/imv.ini;
          output = mkDefault "imv/config";
        };

        # The neovim target's palette as a vim colorscheme, read at
        # startup: vim has no server to send a reload to by default.
        vim = {
          enable = mkDefault programEnabled.vim;
          template = mkDefault ../templates/vim.vim;
          output = mkDefault "vim/colors.vim";
        };

        # A switch within a mode shows after Developer: Reload Window; a
        # mode switch makes VS Code load the other theme, rereading it.
        vscode = {
          enable = mkDefault programEnabled.vscode;
          template = mkDefault ../templates/vscode.json;
          output = mkDefault "vscode/chromix.json";
        };

        # userChrome.css, read when the app starts.
        firefox = {
          enable = mkDefault programEnabled.firefox;
          template = mkDefault ../templates/firefox.css;
          output = mkDefault "firefox/userChrome.css";
        };

        # userContent.css, for Firefox's own about: pages.
        firefox-content = {
          enable = mkDefault cfg.targets.firefox.enable;
          template = mkDefault ../templates/firefox-content.css;
          output = mkDefault "firefox/userContent.css";
        };

        thunderbird = {
          enable = mkDefault programEnabled.thunderbird;
          template = mkDefault ../templates/thunderbird.css;
          output = mkDefault "thunderbird/userChrome.css";
        };

        # An unpacked theme extension, loaded once from chrome://extensions.
        # Its version is made from the theme's colours, so pressing reload
        # there (or restarting) repacks it rather than using the cache.
        chromium = {
          enable = mkDefault programEnabled.chromium;
          template = mkDefault ../templates/chromium.json;
          output = mkDefault "chromium/manifest.json";
        };

        # The frame colour as Chromium's BrowserThemeColor policy, from
        # which Chromium makes a Material palette of its own for all of
        # its UI, menus and settings pages included, where a theme
        # extension only reaches the frame, tabs and toolbar. Not the
        # seed: Chromium paints the frame in the policy colour itself,
        # whatever its mode, so a bright seed makes a light window. A policy
        # is only read from /etc: chromix's NixOS module links it there.
        # Chromium rereads it on start, every 15 minutes, or with
        # Reload policies in chrome://policy.
        chromium-policy = {
          enable = mkDefault cfg.targets.chromium.enable;
          template = mkDefault ../templates/chromium-policy.json;
          output = mkDefault "chromium/policy.json";
        };

        # Read at startup.
        prismlauncher = {
          enable = mkDefault programEnabled.prismlauncher;
          template = mkDefault ../templates/prismlauncher.json;
          output = mkDefault "prismlauncher/theme.json";
        };

        # Only the seed: the folder colour nearest it is picked by
        # chromix-papirus, which rebuilds Papirus-Chromix. GTK apps
        # notice the changed theme on their own after a few seconds.
        papirus = {
          enable = mkDefault programEnabled.papirus;
          template = mkDefault ../templates/papirus.txt;
          output = mkDefault "papirus/seed";
          reload = mkDefault (lib.optionalString (papirus != null) papirusRun);
        };
      };
    }

    (mkIf (active "morph-shell") {
      xdg.stateFile."morph-shell/colors.json".source = link cfg.targets.morph-shell.output;
      # The shell draws the wallpaper itself, from the image the theme
      # was made from; a theme made from a colour leaves it plain.
      xdg.stateFile."morph-shell/wallpaper.json".source = link "chromix.json";
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

    # btop looks themes up by name in its themes directory.
    (mkIf (active "btop") {
      xdg.configFile."btop/themes/chromix.theme".source = link cfg.targets.btop.output;
      programs.btop.settings.color_theme = "chromix";
    })

    # sourceFirst puts this above the widgets that use its variables.
    (mkIf (active "hyprlock") {
      programs.hyprlock.settings.source = ["${current}/${cfg.targets.hyprlock.output}"];
    })

    # yazi picks a flavor per terminal mode; chromix's own follows the
    # mode itself, so it serves both.
    (mkIf (active "yazi") {
      xdg.configFile."yazi/flavors/chromix.yazi/flavor.toml".source = link cfg.targets.yazi.output;
      programs.yazi.theme.flavor = {
        dark = "chromix";
        light = "chromix";
      };
    })

    (mkIf (active "yazi-syntax") {
      xdg.configFile."yazi/flavors/chromix.yazi/tmtheme.xml".source = link cfg.targets.yazi-syntax.output;
    })

    # qt5ct and qt6ct read one scheme file each, wherever it is. A style
    # with a palette of its own (qt.style.name, QT_STYLE_OVERRIDE) wins
    # over this one; Fusion takes it as it is.
    (mkIf (active "qt") (let
      appearance = {
        custom_palette = true;
        color_scheme_path = "${current}/${cfg.targets.qt.output}";
      };
    in {
      qt.qt5ctSettings.Appearance = appearance;
      qt.qt6ctSettings.Appearance = appearance;
    }))

    # Read before FZF_DEFAULT_OPTS, so options set there still apply.
    (mkIf (active "fzf") {
      home.sessionVariables.FZF_DEFAULT_OPTS_FILE = "${current}/${cfg.targets.fzf.output}";
    })

    (mkIf (active "eza") {
      xdg.configFile."eza/theme.yml".source = link cfg.targets.eza.output;
    })

    (mkIf (active "fastfetch") {
      xdg.configFile."fastfetch/config.jsonc".source = link cfg.targets.fastfetch.output;
    })

    (mkIf (active "git") {
      programs.git.includes = [{path = "${current}/${cfg.targets.git.output}";}];
    })

    (mkIf (active "imv") {
      xdg.configFile."imv/config".source = link cfg.targets.imv.output;
    })

    (mkIf (active "vim") {
      programs.vim.extraConfig = ''
        silent! source ${current}/${cfg.targets.vim.output}
      '';
    })

    (mkIf (active "vscode") {
      programs.vscode.profiles.default.extensions = [vscodeExtension];
    })

    # Both stylesheets are read only with this pref.
    (mkIf (active "firefox" || active "firefox-content") {
      programs.firefox.policies.Preferences."toolkit.legacyUserProfileCustomizations.stylesheets" = {
        Value = true;
        Status = "default";
      };
    })

    # Every profile the module declares that has no userChrome of its own.
    (mkIf (active "firefox") {
      home.file = lib.mapAttrs' (_: profile:
        lib.nameValuePair "${config.programs.firefox.profilesPath}/${profile.path}/chrome/userChrome.css" {
          source = link cfg.targets.firefox.output;
        }) (lib.filterAttrs (_: profile: profile.userChrome == "") config.programs.firefox.profiles);
    })

    # And no userContent of its own.
    (mkIf (active "firefox-content") {
      home.file = lib.mapAttrs' (_: profile:
        lib.nameValuePair "${config.programs.firefox.profilesPath}/${profile.path}/chrome/userContent.css" {
          source = link cfg.targets.firefox-content.output;
        }) (lib.filterAttrs (_: profile: profile.userContent == "") config.programs.firefox.profiles);
    })

    (mkIf (active "thunderbird") {
      programs.thunderbird.settings."toolkit.legacyUserProfileCustomizations.stylesheets" = true;
      home.file = lib.mapAttrs' (name: _:
        lib.nameValuePair ".thunderbird/${name}/chrome/userChrome.css" {
          source = link cfg.targets.thunderbird.output;
        }) (lib.filterAttrs (_: profile: profile.userChrome == "") config.programs.thunderbird.profiles);
    })

    # The rest of the profiles, for apps Home Manager does not manage.
    # Firefox keeps them in ~/.mozilla or, since moving to the XDG
    # directories, in ~/.config/mozilla. Both still need the stylesheet
    # pref, set wherever the app is.
    (mkIf (firefoxSheets != [] || thunderbirdSheets != []) {
      home.activation.chromixProfiles = lib.hm.dag.entryAfter ["chromix" "linkGeneration"] (
        linkProfiles "${config.home.homeDirectory}/.mozilla/firefox" firefoxSheets
        + linkProfiles "${config.xdg.configHome}/mozilla/firefox" firefoxSheets
        + linkProfiles "${config.home.homeDirectory}/.thunderbird" thunderbirdSheets
      );
    })

    # A directory of chromix's own: Chromium resolves symlinks when it
    # loads an unpacked extension, so it is a real directory holding a
    # link to the manifest, and loading it once is enough.
    (mkIf (active "chromium") {
      xdg.dataFile."chromix/chromium/manifest.json".source = link cfg.targets.chromium.output;
    })

    (mkIf (active "prismlauncher") {
      xdg.dataFile."PrismLauncher/themes/chromix/theme.json".source = link cfg.targets.prismlauncher.output;
      programs.prismlauncher.settings.ApplicationTheme = mkDefault "chromix";
    })

    # Built at activation too, after current is linked, so the theme is
    # there before the first switch. Use it as gtk.iconTheme.name.
    (mkIf (active "papirus") {
      home.activation.chromixPapirus = lib.hm.dag.entryAfter ["chromix"] ''
        run env XDG_STATE_HOME=${config.xdg.stateHome} XDG_DATA_HOME=${config.xdg.dataHome} \
          ${papirusRun} || echo "chromix: building Papirus-Chromix failed" >&2
      '';
    })
  ]);
}
