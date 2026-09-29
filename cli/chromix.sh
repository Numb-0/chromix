# chromix: switch between themes that Nix built ahead of time, or make
# one from a wallpaper on the spot.
#
# Every theme is a directory of rendered app configs. Apps read theirs
# through $state/current, a symlink, so switching is one atomic rename
# followed by asking each running app to reload.

manifest="${CHROMIX_MANIFEST:-${XDG_CONFIG_HOME:-$HOME/.config}/chromix/manifest.json}"
state="${XDG_STATE_HOME:-$HOME/.local/state}/chromix"

die() {
  echo "chromix: $*" >&2
  exit 1
}

usage() {
  cat <<EOF
usage: chromix <command> [args]

  list                     themes you declared, the current one marked
  status                   the current theme and mode
  set <theme> [dark|light] switch theme, keeping the mode unless given
  mode <dark|light|toggle> switch mode, keeping the theme
  wall <image> [dark|light] generate a theme from an image and switch to it
  refresh [--no-reload]    relink the current selection and reload apps
EOF
}

need_manifest() {
  [ -r "$manifest" ] || die "no manifest at $manifest (is programs.chromix enabled?)"
}

# Renders one theme: a spec (source, mode, scheme type, templates,
# custom colours) in, a directory of app configs out. Nix builds every
# declared theme with this, and `wall` uses it at runtime, so the two
# cannot drift apart.
generate() {
  local spec="$1" out="$2" work
  work="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$work'" RETURN

  jq -r --arg out "$work/out" '
    "[config.custom_colors]",
    (.customColors | to_entries[] | "\(.key | @json) = \(.value | @json)"),
    (.targets[] |
      "",
      "[templates.\(.name | @json)]",
      "input_path = \(.template | @json)",
      "output_path = \(($out + "/" + .output) | @json)")
  ' "$spec" >"$work/config.toml"

  jq -r --arg out "$work/out" '.targets[] | $out + "/" + .output' "$spec" |
    while read -r file; do mkdir -p "$(dirname "$file")"; done

  local mode type contrast color image index
  mode="$(jq -r .mode "$spec")"
  type="$(jq -r .type "$spec")"
  contrast="$(jq -r .contrast "$spec")"
  color="$(jq -r '.source.color // empty' "$spec")"
  image="$(jq -r '.source.image // empty' "$spec")"
  index="$(jq -r '.source.colorIndex // 0' "$spec")"

  local args=(-c "$work/config.toml" -q -m "$mode" -t "$type" --contrast "$contrast")

  # matugen wants somewhere to write a cache, and in the Nix sandbox
  # HOME is not writable.
  if [ -n "$color" ]; then
    HOME="$work" matugen "${args[@]}" color hex "$color"
  elif [ -n "$image" ]; then
    # Without an index matugen stops to ask which colour to use.
    HOME="$work" matugen "${args[@]}" image "$image" --source-color-index "$index"
  else
    die "spec has neither a colour nor an image: $spec"
  fi

  jq '{mode, source}' "$spec" >"$work/out/chromix.json"
  mv "$work/out" "$out"
}

# The selection lives in state.json; current is only ever derived from
# it, so a rebuild that moves every theme to a new store path is fixed
# by `refresh` without losing what was picked.
read_state() {
  if [ -r "$state/state.json" ]; then
    theme="$(jq -r .theme "$state/state.json")"
    mode="$(jq -r .mode "$state/state.json")"
    image="$(jq -r '.image // empty' "$state/state.json")"
  else
    theme="$(jq -r .default.theme "$manifest")"
    mode="$(jq -r .default.mode "$manifest")"
    image=""
  fi
}

# A wallpaper theme is keyed by what went into it, so switching back to
# a wallpaper or toggling its mode twice does not regenerate it.
wallpaper_dir() {
  local key spec
  key="$(
    {
      sha256sum "$image" | cut -d' ' -f1
      echo "$mode"
      jq -c .generator "$manifest"
    } | sha256sum | cut -c1-16
  )"
  local dir="$state/generated/$key"

  if [ ! -d "$dir" ]; then
    mkdir -p "$state/generated"
    spec="$(mktemp)"
    jq --arg image "$image" --arg mode "$mode" \
      '.generator + {source: {image: $image}, mode: $mode}' "$manifest" >"$spec"
    generate "$spec" "$dir.tmp" || { rm -f "$spec"; rm -rf "$dir.tmp"; die "could not generate a theme from $image"; }
    rm -f "$spec"
    mv "$dir.tmp" "$dir"
  fi

  # Only the one in use is worth keeping.
  find "$state/generated" -mindepth 1 -maxdepth 1 ! -path "$dir" -exec rm -rf {} +
  echo "$dir"
}

apply() {
  local reload="$1" dir

  if [ "$theme" = "wallpaper" ]; then
    [ -r "$image" ] || die "wallpaper not found: $image"
    dir="$(wallpaper_dir)"
  else
    dir="$(jq -r --arg t "$theme" --arg m "$mode" '.themes[$t][$m] // empty' "$manifest")"
    [ -n "$dir" ] || die "no theme '$theme' (try: chromix list)"
  fi

  mkdir -p "$state"
  ln -sfn "$dir" "$state/current.new"
  mv -T "$state/current.new" "$state/current"

  jq -n --arg theme "$theme" --arg mode "$mode" --arg image "$image" \
    '{theme: $theme, mode: $mode} + (if $image != "" then {image: $image} else {} end)' \
    >"$state/state.json"

  if [ "$reload" = 1 ]; then
    CHROMIX_THEME="$theme" CHROMIX_MODE="$mode" CHROMIX_CURRENT="$state/current" \
      "$(jq -r .reload "$manifest")"
  fi
}

check_mode() {
  case "$1" in
  dark | light) ;;
  *) die "mode must be dark or light, not '$1'" ;;
  esac
}

cmd="${1:-}"
[ $# -gt 0 ] && shift

case "$cmd" in
list)
  need_manifest
  read_state
  jq -r '.themes | keys[]' "$manifest" | while read -r t; do
    if [ "$t" = "$theme" ]; then echo "* $t"; else echo "  $t"; fi
  done
  ;;
status)
  need_manifest
  read_state
  echo "theme: $theme${image:+ ($image)}"
  echo "mode:  $mode"
  echo "path:  $(readlink "$state/current" 2>/dev/null || echo "(not applied yet)")"
  ;;
set)
  need_manifest
  [ $# -ge 1 ] || die "usage: chromix set <theme> [dark|light]"
  read_state
  theme="$1"
  image=""
  [ $# -ge 2 ] && check_mode "$2" && mode="$2"
  apply 1
  ;;
mode)
  need_manifest
  [ $# -eq 1 ] || die "usage: chromix mode <dark|light|toggle>"
  read_state
  if [ "$1" = toggle ]; then
    if [ "$mode" = dark ]; then mode=light; else mode=dark; fi
  else
    check_mode "$1"
    mode="$1"
  fi
  apply 1
  ;;
wall)
  need_manifest
  [ $# -ge 1 ] || die "usage: chromix wall <image> [dark|light]"
  read_state
  theme=wallpaper
  image="$(realpath "$1")" || die "wallpaper not found: $1"
  [ $# -ge 2 ] && check_mode "$2" && mode="$2"
  apply 1
  ;;
refresh)
  need_manifest
  read_state
  # A theme dropped from the config since it was picked: fall back to
  # the default rather than leave current dangling.
  if [ "$theme" != wallpaper ] && [ "$(jq --arg t "$theme" '.themes | has($t)' "$manifest")" != true ]; then
    theme="$(jq -r .default.theme "$manifest")"
  fi
  if [ "${1:-}" = --no-reload ]; then apply 0; else apply 1; fi
  ;;
generate)
  # Internal: used by the Nix build.
  [ $# -eq 2 ] || die "usage: chromix generate <spec.json> <out>"
  generate "$1" "$2"
  ;;
"" | -h | --help | help)
  usage
  ;;
*)
  usage >&2
  exit 1
  ;;
esac
