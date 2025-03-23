{
  description = "A NixOS flake that produces a VM QCOW2 image";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      run-qemu-image = pkgs.writeShellScriptBin "run-qemu-image" ''
        #!/usr/bin/env bash
        set -e

        QEMU_IMAGE="qemu-image:latest"
        VM_IMAGE="$PWD/build/nixos.qcow2"

        echo "Loading Docker image..."
        docker load < ${self.qemuImage.${system}}

        echo "Copying VM image..."
        rm -rf build
        mkdir -p build
        cp "${self.packages.${system}.qcow2}/nixos.qcow2" "$VM_IMAGE"

        echo "Running Docker container..."
        docker run --privileged --rm -d -p 2222:2222 -p 25560:25560 -v "$VM_IMAGE":/app.qcow2 "$QEMU_IMAGE"
      '';
      startVmScript = builtins.readFile ./startvm.sh;
    in {
      devShells = {
        default = pkgs.mkShell {
          buildInputs = [
            run-qemu-image
          ];
        };
      };

      qemuImage = pkgs.dockerTools.buildImage {
        name = "qemu-image";
        tag = "latest";

        copyToRoot = [
          pkgs.qemu_full
          pkgs.busybox
          pkgs.coreutils
          pkgs.htop
          pkgs.bash
          pkgs.socat
          (pkgs.writeScriptBin "startvm" startVmScript)
        ];

        config = {
          Cmd = ["startvm"];
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
        qcow2 = self.nixosConfigurations.${system}.vm.config.system.build.qcow2;
        qemuImage = self.qemuImage.${system};
        all = pkgs.runCommand "all-outputs" {} ''
          mkdir -p $out/images
          cp -L ${self.qemuImage.${system}} $out/images/qemu-image.tar.gz
        '';
      };
    });
}
