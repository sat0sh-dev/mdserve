{
  description = "mdserve - Instant MkDocs server for any directory";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Python environment with MkDocs and plugins
        pythonEnv = pkgs.python3.withPackages (ps: with ps; [
          mkdocs
          mkdocs-material
          mkdocs-material-extensions
          mkdocs-mermaid2-plugin
        ]);

        # Main mdserve script
        mdserve = pkgs.writeShellApplication {
          name = "mdserve";
          runtimeInputs = [
            pythonEnv
            pkgs.coreutils
            pkgs.findutils
            pkgs.gnugrep
          ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
            pkgs.inotify-tools
          ];
          text = builtins.readFile ./mdserve.sh;
        };
      in
      {
        packages = {
          default = mdserve;
          mdserve = mdserve;
        };

        apps = {
          default = {
            type = "app";
            program = "${mdserve}/bin/mdserve";
          };
        };

        devShells.default = pkgs.mkShell {
          packages = [ mdserve ];
        };
      }
    );
}
