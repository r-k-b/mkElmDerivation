elmSrcsFunc:
with builtins;
{ # Optional: The name of the elm project. Read from "name" key in
  # elm.json if not specified.
  pname ? (fromJSON (readFile elmJson))."name"

# Optional: The version of the elm projec. Read from "version" key in
# elm.json if not specified.
, version ? (fromJSON (readFile elmJson))."version"

# The nixpkgs to use (typically of the form
# nixpkgs.legacyPackages.${system}).
, nixpkgs

# The base directory of your elm project (most likely ./.).
, src

# Optional: The elm projects elm.json file. Will default to
# ${src}/elm.json
, elmJson ? "${src}/elm.json"

# Optional: The nix expression containing the elm projects dependency
# names, versions and SHA256 hashes. This will be generated
# automatically, but can be ready from a file generated by
# elm2nix convert. This must be a nix expression, not a file, so to
# use an existing nix expression, set this equal to
# (import ./elm-srcs.nix).
, elmPackages ? elmSrcsFunc elmJson

# Optional: The directory containing the .elm files to
# compile. Currently, we only support using one directory.
, srcdir ? "${src}/${head ((fromJSON (readFile elmJson))."source-directories")}"

# Optional: The version of elm used. Read from elm.json file.
, elmVersion ? (fromJSON (readFile elmJson))."elm-version"

# Optional: The files in srcdir to compile.
, targets ? ["Main"]

# Optional: The output of elm2nix snapshot. There is a copy of this
# file with this repository which is used by default.
, registryDat ? ./registry.dat

# Optional: Should the outputted files by JavaScript or HTML?
, outputJavaScript ? false
}:

with nixpkgs;
stdenv.mkDerivation {
  inherit pname version src;

  buildInputs = [ nixpkgs.elmPackages.elm ]
                ++ lib.optional outputJavaScript nodePackages.uglify-js;

  buildPhase = pkgs.elmPackages.fetchElmDeps {
    inherit elmPackages elmVersion registryDat;
  };

  installPhase =
    let elmfile = module: "${srcdir}/${builtins.replaceStrings ["."] ["/"] module}.elm";
        extension = if outputJavaScript then "js" else "html";
    in ''
       mkdir -p $out/share/doc
       ${lib.concatStrings (map (module: ''
         echo "compiling ${elmfile module}"
         elm make ${elmfile module} --optimize --output $out/${module}.${extension} --docs $out/share/doc/${module}.json
         ${lib.optionalString outputJavaScript ''
          echo "minifying ${elmfile module}"
          uglifyjs $out/${module}.${extension} --compress 'pure_funcs="F2,F3,F4,F5,F6,F7,F8,F9,A2,A3,A4,A5,A6,A7,A8,A9",pure_getters,keep_fargs=false,unsafe_comps,unsafe' \
              | uglifyjs --mangle --output $out/${module}.min.${extension}
      ''}
    '') targets)}
  '';
}
