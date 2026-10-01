# chromix-papirus: recolour Papirus's folders after the current theme.
#
# Papirus sits read-only in the store, so papirus-folders cannot relink
# it in place. This builds Papirus-Chromix instead: a small icon theme
# that inherits Papirus-Dark (or Papirus-Light in light mode) and holds
# only folder icons, linked to the Papirus colour nearest the theme's
# seed. Each colour and mode is built once and kept while in use; a
# switch repoints one symlink.
#
# usage: chromix-papirus <papirus share/icons dir> <seed file in the theme>

icons="$1"
seed_file="$2"

state="${XDG_STATE_HOME:-$HOME/.local/state}/chromix"
current="${CHROMIX_CURRENT:-$state/current}"
data="${XDG_DATA_HOME:-$HOME/.local/share}"

seed="$(tr -d '[:space:]' <"$current/$seed_file")"
mode="$(jq -r .mode "$current/chromix.json")"
if [ "$mode" = light ]; then base=Papirus-Light; else base=Papirus-Dark; fi

# Each colour's folder face, from Papirus's own SVGs. black, white and
# yaru are left out: no seed should land on them.
palette="adwaita:93c0ea blue:5294e2 bluegrey:607d8b breeze:57b8ec brown:ae8e6c
carmine:a30002 cyan:00bcd4 darkcyan:45abb7 deeporange:eb6637 green:87b158
grey:8e8e8e indigo:5c6bc0 magenta:ca71df nordic:81a1c1 orange:ee923a
palebrown:d1bfae paleorange:eeca8f pink:f06292 red:e25252 teal:16a085
violet:7e57c2 yellow:f9bd30"
all_colors="adwaita|black|blue|bluegrey|breeze|brown|carmine|cyan|darkcyan|deeporange|green|grey|indigo|magenta|nordic|orange|palebrown|paleorange|pink|red|teal|violet|white|yaru|yellow"

# Nearest in OKLab, with lightness at a fifth of its weight: a dark seed
# should still find its hue rather than whatever folder is as dark.
color="$(echo "$palette" | tr ' ' '\n' | awk -F: -v seed="$seed" '
  function lin(c) { c /= 255; return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ^ 2.4 }
  function cbrt(x) { return x < 0 ? -((-x) ^ (1 / 3)) : x ^ (1 / 3) }
  function oklab(hex, out,   r, g, b, l, m, s) {
    r = lin(strtonum("0x" substr(hex, 1, 2)))
    g = lin(strtonum("0x" substr(hex, 3, 2)))
    b = lin(strtonum("0x" substr(hex, 5, 2)))
    l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    out["L"] = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    out["a"] = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    out["b"] = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
  }
  BEGIN { sub(/^#/, "", seed); oklab(seed, S); best = 1e9 }
  NF == 2 {
    oklab($2, C)
    d = (0.2 * (C["L"] - S["L"])) ^ 2 + (C["a"] - S["a"]) ^ 2 + (C["b"] - S["b"]) ^ 2
    if (d < best) { best = d; name = $1 }
  }
  END { print name }
')"

dir="$state/papirus/$base-$color"

if [ ! -d "$dir" ]; then
  tmp="$dir.tmp"
  rm -rf "$tmp"
  sizes="22x22 24x24 32x32 48x48 64x64"

  for size in $sizes; do
    src="$icons/$base/$size/places"
    [ -d "$src" ] || continue
    mkdir -p "$tmp/$size/places"

    # Every name whose chain ends at a default (blue) folder icon, aliases
    # such as inode-directory included, goes to the same icon in the
    # chosen colour. Names that spell out a colour keep theirs.
    names="$(cd "$src" && find . -maxdepth 1 -name '*.svg' -printf '%f\n' | sort)"
    targets="$(cd "$src" && echo "$names" | xargs -d '\n' readlink -f)"
    paste <(echo "$names") <(echo "$targets") |
      awk -F'\t' -v color="$color" -v colors="$all_colors" '
        $1 ~ ("^(folder|user)-(" colors ")(-|\\.svg$)") { next }
        {
          n = split($2, parts, "/"); file = parts[n]
          if (file !~ /^(folder|user)-blue(-.*)?\.svg$/) next
          sub(/-blue/, "-" color, file)
          print $1 "\t" file
        }' |
      while IFS="$(printf '\t')" read -r name file; do
        [ -e "$src/$file" ] && ln -s "$(readlink -f "$src/$file")" "$tmp/$size/places/$name"
      done
  done

  # The base theme's own entries for these directories, under a header
  # that names the overlay and hands everything else to the base.
  awk -v base="$base" -v sizes="$sizes" '
    BEGIN {
      n = split(sizes, s, " ")
      for (i = 1; i <= n; i++) { want["[" s[i] "/places]"] = 1; dirs = dirs (i > 1 ? "," : "") s[i] "/places" }
      print "[Icon Theme]"
      print "Name=Papirus-Chromix"
      print "Comment=Papirus with folders in the colour of the current chromix theme"
      print "Inherits=" base
      print "Directories=" dirs
    }
    /^\[/ { keep = ($0 in want); if (keep) print "" }
    keep { print }
  ' "$icons/$base/index.theme" >"$tmp/index.theme"

  mkdir -p "$state/papirus"
  mv "$tmp" "$dir"
fi

mkdir -p "$data/icons"
ln -sfn "$dir" "$data/icons/Papirus-Chromix.new"
mv -T "$data/icons/Papirus-Chromix.new" "$data/icons/Papirus-Chromix"

# Only the one in use is worth keeping.
find "$state/papirus" -mindepth 1 -maxdepth 1 ! -path "$dir" -exec rm -rf {} +
