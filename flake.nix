{
  description = "impasto: a Hyprland shell on Quickshell, packaged for Nix";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forEachSupportedSystem =
        buildOutputs:
        nixpkgs.lib.genAttrs supportedSystems (system: buildOutputs nixpkgs.legacyPackages.${system});
    in
    {
      packages = forEachSupportedSystem (pkgs: rec {
        impasto-shell = pkgs.callPackage ./nix/package.nix {
          sourceRevision = self.shortRev or self.dirtyShortRev or "unknown";
        };
        default = impasto-shell;
      });

      overlays.default = final: _previous: {
        impasto-shell = final.callPackage ./nix/package.nix {
          sourceRevision = self.shortRev or self.dirtyShortRev or "unknown";
        };
      };
    };
}
