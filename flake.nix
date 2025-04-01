{
  description = "A NixOS flake that produces a VM QCOW2 image";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
    stasis-tools.url = "path:./stasis-tools";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    stasis-tools,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      startVmScript = builtins.readFile ./startvm.sh;
      stasisTools = stasis-tools.packages.${system}.default;
      nixosNixImage = pkgs.dockerTools.pullImage {
        imageName = "nixos/nix";
        imageDigest = "sha256:cf7ba2afcacd7be9171259d209d2d1ae6ab183b5c561c7e7524a9bc1d8fddaa1";
        hash = "sha256-GP/kgRTFISRnF+pYd9dgufl/M1U9BVi/aUJzgXaPzdc=";
        finalImageName = "nixos/nix";
        finalImageTag = "latest";
      };
    in {
      devShells = {
        default = pkgs.mkShell {
          buildInputs = [
            pkgs.alejandra
            pkgs.gnumake
          ];
        };
      };

      image = pkgs.dockerTools.buildImage {
        name = "qemu-image";
        tag = "latest";

        fromImage = nixosNixImage;

        copyToRoot = [
          pkgs.qemu_kvm
          pkgs.busybox
          pkgs.coreutils
          pkgs.bash
          pkgs.socat
          (pkgs.writeScriptBin "startvm" startVmScript)
          stasisTools
          (pkgs.writeScriptBin "entrypoint" ''
            #!/bin/sh
            # Ensure /bin is in PATH regardless of environment variables
            export PATH="/bin:$PATH"
            exec "$@"
          '')
          (pkgs.runCommand "nix-scripts" {} ''
            mkdir -p $out/app
            cp -r ${./flake.nix} $out/app/flake.nix
            cp -r ${./flake.lock} $out/app/flake.lock
            cp -r ${./make-qcow2.nix} $out/app/make-qcow2.nix
            cp -r ${./vm-config.nix} $out/app/vm-config.nix
            cp -r ${./stasis-tools} $out/app/stasis-tools
            cp -r ${./startvm.sh} $out/app/startvm.sh
          '')
        ];

        config = {
          Entrypoint = ["/bin/entrypoint"];
          Cmd = ["startvm"];
          Env = [
            "NIX_CONFIG=experimental-features = nix-command flakes"
          ];
        };
      };

      nixosConfigurations = {
        vm = nixpkgs.lib.nixosSystem {
          system = system;
          modules = [
            ./vm-config.nix
            ./make-qcow2.nix
          ];
        };
      };

      packages = {
        vm = self.nixosConfigurations.${system}.vm.config.system.build.qcow2;
        image = self.image.${system};
        all = pkgs.runCommand "all-outputs" {} ''
          mkdir -p $out/images
          cp -L ${self.image.${system}} $out/images/qemu-image.tar.gz
        '';
      };
    });
}
