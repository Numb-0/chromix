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

Inspired by [vogix](https://github.com/i-am-logger/vogix) (prebuilt
themes behind one symlink) and [Stylix](https://github.com/danth/stylix)
(declarative app targets).

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

**Configuring an app outside Home Manager?** Add it as
[your own target](#your-own-targets) instead, reusing the built-in
template, and point the app at the file yourself.

**Coming from Stylix?** Turn off its targets for the apps chromix themes,
or the two will overwrite each other (`stylix.targets.kitty.enable = false;`
and so on).

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
red, green, yellow, blue, magenta and cyan for terminal ANSI colours, and
success and warning. matugen nudges each towards the seed while keeping
its hue, and generates `on_`, `_container` and `on_…_container` tones for
each. Change a hue with `programs.chromix.customColors.red = "#…";`.
