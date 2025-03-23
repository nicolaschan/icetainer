{
  description = "A NixOS flake that produces a VM QCOW2 image";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
    icetainer-tools.url = "path:./icetainer-tools";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    icetainer-tools
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      startVmScript = builtins.readFile ./startvm.sh;
      icetainerTools = icetainer-tools.packages.${system}.default;
    in {
      devShells = {
        default = pkgs.mkShell {
          buildInputs = [
            pkgs.alejandra
            pkgs.gnumake
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
          icetainerTools
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
