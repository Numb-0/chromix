{
  lib,
  writeShellApplication,
  coreutils,
  findutils,
  jq,
  matugen,
}:
writeShellApplication {
  name = "chromix";
  runtimeInputs = [coreutils findutils jq matugen];
  text = builtins.readFile ../cli/chromix.sh;
  meta = {
    description = "Runtime theme switcher for themes built with Nix and matugen";
    license = lib.licenses.mit;
    mainProgram = "chromix";
  };
}
