{
  lib,
  ruby,
  gemset,
  buildRubyGem,
  fetchurl,
  privateRegistryHostname,
  ...
}@args:

with builtins;
with lib;
rec {

  # captures matching gem versions(variants)
  gemsetVersions =
    let
      inherit (import ./filters.nix args) filterGemset;
      inherit (import ./expand.nix args) mapGemsetVersions;
    in
    pipe gemset [
      filterGemset
      mapGemsetVersions
    ];

  # `gemPath` will be passed to `propagatedBuildInputs` and
  # `propagatedUserEnvPkgs` of the gem derivation
  applyDependencies = spec: spec // { gemPath = concatMap (d: gems.${d}) spec.dependencies; };

  suffix =
    spec:
    if (spec ? platform) && spec.platform != "ruby" then
      "${spec.version}-${spec.platform}"
    else
      spec.version;

  fetchPrivateGemSource =
    spec:
    if privateRegistryHostname != null && privateRegistryHostname != "" then
      if
        (spec.source ? remotes)
        && (builtins.length spec.source.remotes == 1)
        && (lib.hasInfix privateRegistryHostname (builtins.head spec.source.remotes))
      then
        spec
        // {
          src = fetchurl {
            url = "${builtins.head spec.source.remotes}/gems/${spec.gemName}-${suffix spec}.gem";
            sha256 = spec.source.sha256;
            netrcImpureEnvVars = [
              "NIX_GEM_REGISTRY_LOGIN"
              "NIX_GEM_REGISTRY_PASSWORD"
            ];
            netrcPhase = ''
              # Check if required env vars are set at build time
              if [ -z "$NIX_GEM_REGISTRY_LOGIN" ] || [ -z "$NIX_GEM_REGISTRY_PASSWORD" ]; then
                echo "Error: NIX_GEM_REGISTRY_LOGIN and NIX_GEM_REGISTRY_PASSWORD must be set"
                exit 1
              fi

              cat > netrc <<EOF
              machine ${privateRegistryHostname}
              login $NIX_GEM_REGISTRY_LOGIN
              password $NIX_GEM_REGISTRY_PASSWORD
              EOF
              chmod 600 netrc
            '';
          };
        }
      else
        spec
    else
      spec;

  gems = flip mapAttrs gemsetVersions (
    _: versions:
    pipe versions [
      (map applyDependencies)
      (map fetchPrivateGemSource)
      (map (spec: buildRubyGem (spec // { inherit ruby; })))
    ]
  );

  gempaths = pipe gems (
    with lib;
    [
      attrValues
      (concatMap id)
    ]
  );
}
