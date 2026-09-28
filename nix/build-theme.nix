# One theme in one mode, rendered for every enabled target. The same
# `chromix generate` does it at runtime for wallpapers, so a theme built
# here and one made with `chromix wall` go through identical code.
{
  runCommand,
  writeText,
  chromix,
}: {
  name,
  mode,
  source,
  generator,
}:
runCommand "chromix-${name}-${mode}" {nativeBuildInputs = [chromix];} ''
  chromix generate ${writeText "chromix-${name}-${mode}.json" (builtins.toJSON (generator // {inherit mode source;}))} $out
''
