# chromix-profiles: link stylesheets into every profile of a Mozilla app
# that Home Manager is not told about.
#
# The profiles are read from the app's profiles.ini, so profiles made
# by hand or by the app itself are themed without naming them. Each
# file is a link through current/, made once; a switch needs nothing
# here. A file of the profile's own (not a symlink) is left alone.
#
# usage: chromix-profiles <profiles dir> <file in chrome/>=<path> ...

root="$1"
shift

ini="$root/profiles.ini"
[ -r "$ini" ] || exit 0

# One "<IsRelative>\t<Path>" line per [Profile*] section.
awk -F= '
  /^\[/ { if (path != "") print rel "\t" path; path = ""; rel = 1; next }
  $1 == "IsRelative" { rel = $2 }
  $1 == "Path" { path = substr($0, 6) }
  END { if (path != "") print rel "\t" path }
' "$ini" | while IFS=$'\t' read -r rel path; do
  [ "$rel" = 1 ] && path="$root/$path"
  [ -d "$path" ] || continue

  for pair in "$@"; do
    dest="$path/chrome/${pair%%=*}"
    if [ -e "$dest" ] && [ ! -L "$dest" ]; then
      echo "chromix: $dest is not a link, leaving it alone" >&2
      continue
    fi
    mkdir -p "$path/chrome"
    ln -sfn "${pair#*=}" "$dest"
  done
done
