# chromix

Runtime theme switching for Nix. Themes are Material 3 schemes that
[matugen](https://github.com/InioX/matugen) generates from a seed colour
or an image. Nix renders every theme you declare for every app you theme
ahead of time, and switching is a symlink swap plus a reload — no rebuild.

```sh
chromix set ember           # another prebuilt theme
chromix mode toggle         # dark <-> light
chromix wall ~/walls/x.png  # a theme from an image, generated on the spot
chromix list | status | refresh
```

Inspired by [vogix](https://github.com/i-am-logger/vogix) and [Stylix](https://github.com/danth/stylix)

## How it works

```
programs.chromix.themes ──(Nix: matugen × templates)──▶ /nix/store/…-chromix-ocean-dark/
                                                           kitty/colors.conf
                                                           hyprland/colors.lua
                                                           morph-shell/colors.json …

~/.local/state/chromix/current ──▶ the theme in use        (the only thing a switch changes)
~/.config/kitty/kitty.conf: include …/current/kitty/colors.conf
```

- **Build time.** Each theme is built in dark and light by
  `chromix generate`, which renders the enabled targets' matugen
  templates into one directory.
- **Switching.** `chromix set` repoints `current` atomically, records
  the choice in `state.json`, then runs each target's reload command.
- **Wallpapers.** `chromix wall` runs the same `chromix generate` at
  runtime into `~/.local/state/chromix/generated/`, so prebuilt and
  wallpaper themes cannot drift apart.
- **Rebuilds.** Home Manager activation re-links `current` to the new
  store paths and keeps whatever you last picked.

## Setup

```nix
# flake.nix
inputs.chromix = {
  url = "github:Numb-0/chromix";
  inputs.nixpkgs.follows = "nixpkgs";
};

# home-manager
imports = [ inputs.chromix.homeManagerModules.default ];

programs.chromix = {
  enable = true;
  themes = {
    ocean.color = "#1e88e5";
    ember = { color = "#e53935"; type = "scheme-expressive"; };
    forest.image = ./walls/forest.jpg;
    # The second colour matugen pulls from the image, not the first.
    dunes = { image = ./walls/dunes.png; colorIndex = 1; };
  };
  default = { theme = "ocean"; mode = "dark"; };
};
```

## Targets

A built-in target switches on with its app's Home Manager module
(`programs.kitty.enable` and so on). Turn one off to leave that app
alone:

```nix
programs.chromix.targets.gtk.enable = false;
```

Without the module, a target does nothing, even when enabled: no theme
is rendered or linked for an app that is not there.

| Target | Needs | Wired in through | Live reload |
|---|---|---|---|
| `morph-shell` | `programs.morph-shell` | `~/.local/state/morph-shell/colors.json` | `morph-shell ipc call palette reload`, fades |
| `kitty` | `programs.kitty` | `include` in `programs.kitty.extraConfig` | `SIGUSR1` |
| `hyprland` | `wayland.windowManager.hyprland` | `pcall(dofile, …)` (Lua config) or `source =` (hyprlang) in `extraConfig` | `hyprctl reload` |
| `gtk` | `gtk` | `@import` in `gtk.gtk{3,4}.extraCss` | libadwaita follows `color-scheme`; `gtk.css` on next launch |
| `neovim` | `programs.neovim` | `mini.base16` + `dofile` in `programs.neovim` | `luafile` over every nvim server |
| `btop` | `programs.btop` | `~/.config/btop/themes/chromix.theme` + `color_theme` in `programs.btop.settings` | `SIGUSR2` |
| `hyprlock` | `programs.hyprlock` | `source =` in `programs.hyprlock.settings`: `$m3…` colour variables and `$wallpaper` for your widgets | none needed, read on every lock |
| `hyprpaper` | `services.hyprpaper` | `source =` in `services.hyprpaper.settings`: the theme's image on every monitor (none for colour themes) | restarts `hyprpaper.service` |
| `yazi` | `programs.yazi` | `~/.config/yazi/flavors/chromix.yazi/flavor.toml` + `flavor` in `programs.yazi.theme` | `ya emit-to 0 app:theme` |

**How the base16 palette is built.** A base16 scheme needs eight
neutrals and eight accent hues, more than Material's roles provide.
matugen's own base16 output has only four distinct hues among its seven
accents, and one accent set for both modes. chromix builds the palette
itself. The `neovim` target uses it through `mini.base16`, and any
base16 template of yours can use the same mapping:

| Slots | Used for | Taken from |
|---|---|---|
| `base00`–`base07` | page, cursor line, separators, comments, text | the seed's surface and outline roles, so they switch with the mode |
| `base08`–`base0E` | variables, constants, types, strings, escapes, functions, keywords | the red, orange, yellow, green, cyan, blue and magenta custom colours |
| `base0F` | delimiters | `on_surface_variant`, kept neutral |

Each accent keeps its own hue and leans only slightly towards the seed,
so any seed gives seven distinct hues, toned to read on the page in
either mode.

**Configuring an app outside Home Manager?** Enable its target anyway
(`targets.neovim.enable = true;`): the file is rendered and reloaded,
just not wired in, so point the app at it yourself.

### Your own targets

A target is a matugen template, where its output lands, and a reload:

```nix
programs.chromix.targets.foot = {
  enable = true;
  template = ./foot.ini;          # {{colors.primary.default.hex_stripped}} …
  output = "foot/colors.ini";
  reload = "pkill -USR1 -x foot || true";
};
```

Templates see every M3 role (`colors.<role>`), plus the custom colours:
red, green, yellow, blue, magenta and cyan for terminal ANSI colours,
orange to complete the base16 palette, and success and warning.
The seed stays the centre and the custom colours are pulled towards it.
matugen rotates each one's hue a little towards the seed's hue (by at most about 15°),
so red stays red. It thenpicks tones that read on the mode's page and generates `on_`,
`_container` and `on_…_container` tones for each. Change a hue with
`programs.chromix.customColors.red = "#…";`.
