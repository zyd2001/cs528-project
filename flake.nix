{
  description = "MicroVM with auto-started Python app (8 GiB writable store)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";

    # ← the microvm module lives here
    microvm.url = "github:astro/microvm.nix";
    microvm.inputs.nixpkgs.follows = "nixpkgs";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    microvm,
    uv2nix,
    ...
  } @ inputs:
    flake-utils.lib.eachDefaultSystem (system: let
      inherit (nixpkgs) lib;

      gradio-server-script = uv2nix.lib.scripts.loadScript {
        script = ./server.py;
      };

      # Create package overlay from workspace.
      overlay = gradio-server-script.mkOverlay {
        sourcePreference = "wheel"; # or sourcePreference = "sdist";
      };

      # Use Python 3.12 from nixpkgs
      python = pkgs.python312;

      # Construct package set
      pythonSet =
        # Use base package set from pyproject.nix builders
        (pkgs.callPackage inputs.pyproject-nix.build.packages {
          inherit python;
        })
        .overrideScope
        (
          lib.composeManyExtensions [
            inputs.pyproject-build-systems.overlays.default
            overlay
          ]
        );

      # first build the raw venv
      rawVenv = gradio-server-script.mkVirtualEnv {inherit pythonSet;};

      # then override its fixupPhase to remove the reflexive link
      venv = rawVenv.overrideAttrs (old: {
        fixupPhase = ''
          echo "→ removing reflexive env-vars symlink from venv"
          rm -f $out/env-vars
        '';
      });

      pkgs = import nixpkgs {inherit system;};

      gradio-server = pkgs.writeScriptBin gradio-server-script.name (
        gradio-server-script.renderScript {
          inherit venv;
        }
      );

      /*
      # ── single-file Python app ────────────────────────────────
      gradio-server = pkgs.stdenvNoCC.mkDerivation {
        pname   = "gradio server";
        version = "0.0.1";
        format  = "other";
        src     = ./server.py;
        buildInputs = [ venv ];

        unpackPhase  = ''cp $src server.py'';
        installPhase = ''
          install -Dm755 server.py $out/bin/gradio-server
          wrapProgram $out/bin/gradio-server \
            --set PATH ${lib.makeBinPath (with pkgs; [
              nodejs_22
              which
            ])}
        '';
        meta.mainProgram = "gradio-server";
      };
      */

      # ── NixOS module for the MicroVM ──────────────────────────
      vmModule = {
        lib,
        config,
        ...
      }: {
        imports = [microvm.nixosModules.microvm];

        # resource limits & hypervisor
        microvm.vcpu = 2; # CPU cores :contentReference[oaicite:0]{index=0}
        microvm.mem = 2560; # MiB       :contentReference[oaicite:1]{index=1}
        microvm.hypervisor = "qemu"; # or "firecracker", "cloud-hypervisor", …
        microvm.storeDiskErofsFlags = ["-zlz4hc"];

        # 8 GiB *writable* overlay for /nix/store so the VM can’t
        # exhaust host disk space
        microvm.writableStoreOverlay = "/nix/.rw-store";
        microvm.volumes = [
          {
            image = "nix-store-overlay.img";
            mountPoint = config.microvm.writableStoreOverlay;
            size = 8 * 1024; # MiB -> 8 GiB limit :contentReference[oaicite:2]{index=2}
          }
        ];

        microvm.interfaces = [
          {
            type = "user";
            id = "net0";
            mac = "02:00:00:00:00:10";
          }
        ];

        # forward host :2222 → guest :22 for SSH
        microvm.forwardPorts = [
          {
            host.port = 2222;
            guest.port = 22;
          }
          {
            host.port = 7860;
            guest.port = 7860;
          }
        ];

        # inside-guest setup
        services.openssh.enable = true;
        users.users.root.password = "root";
        environment.systemPackages = [gradio-server];

        systemd.services.gradio-server = {
          description = "gradio server service";
          wantedBy = ["multi-user.target"];
          requires = ["network-online.target"];
          after = ["network-online.target"];
          restartIfChanged = true;
          serviceConfig = {
            DynamicUser = true;
            ExecStart = lib.getExe gradio-server;
            Restart = "on-failure";
          };
        };

        networking.firewall.enable = false;

        # lock in a release so future upgrades are explicit
        system.stateVersion = lib.trivial.release;
      };
    in {
      formatter = pkgs.alejandra;
      # build the NixOS system
      nixosConfigurations.server = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [vmModule];
      };

      # expose the MicroVM runner script as a package and default app
      packages.gradio-server-vm = self.nixosConfigurations.${system}.server.config.microvm.declaredRunner;
      packages.gradio-server = gradio-server;
      defaultPackage = self.packages.${system}.gradio-server-vm;
      apps.default = {
        type = "app";
        program = "${self.packages.${system}.gradio-server-vm}/bin/microvm-run";
      };
    });
}
