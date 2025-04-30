{
  description = "MicroVM with auto-started Python app (8 GiB writable store)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
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
      pkgs = import nixpkgs {inherit system;};

      # Use Python 3.12 from nixpkgs
      python = pkgs.python312;

      mkScript = script-name: let
        script = uv2nix.lib.scripts.loadScript {
          script = script-name;
        };

        # Create package overlay from workspace.
        overlay = script.mkOverlay {
          sourcePreference = "wheel"; # or sourcePreference = "sdist";
        };

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
        rawVenv = script.mkVirtualEnv {inherit pythonSet;};

        # then override its fixupPhase to remove the reflexive link
        venv = rawVenv.overrideAttrs (old: {
          fixupPhase = ''
            echo "→ removing reflexive env-vars symlink from venv"
            rm -f $out/env-vars
          '';
        });
      in
        pkgs.writeScriptBin script.name (
          script.renderScript {
            inherit venv;
          }
        );

      gradio-server = mkScript ./server.py;
      exploit = mkScript ./exploit.py;

      # ── NixOS module for the MicroVM ──────────────────────────
      vmModule = {
        lib,
        config,
        ...
      }: {
        imports = [microvm.nixosModules.microvm];

        nix.settings.experimental-features = [ "nix-command" "flakes" ];

        # resource limits & hypervisor
        microvm.vcpu = 2; # CPU cores :contentReference[oaicite:0]{index=0}
        microvm.mem = 2560; # MiB       :contentReference[oaicite:1]{index=1}
        microvm.hypervisor = "qemu"; # or "firecracker", "cloud-hypervisor", …
        microvm.storeDiskErofsFlags = ["-zlz4hc"];
        microvm.optimize.enable = true;

        # 8 GiB *writable* overlay for /nix/store so the VM can’t
        # exhaust host disk space
        microvm.writableStoreOverlay = "/nix/.rw-store";
        microvm.volumes = [
          {
            image = "nix-store-overlay.img";
            mountPoint = config.microvm.writableStoreOverlay;
            size = 4 * 1024; # MiB -> 8 GiB limit :contentReference[oaicite:2]{index=2}
          }
          {
            image = "tmp.img";
            mountPoint = "/tmp";
            size = 2 * 1024;
          }
          {
            image = "www.img";
            mountPoint = "/var/www";
            size = 50;
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
            from = "host";
            proto = "tcp";
            host.port = 2222;
            guest.address = "10.0.2.15"; # …to the VM’s SLiRP IP (default 10.0.2.15)…
            guest.port = 22;
          }
          {
            from = "host";
            proto = "tcp";
            host.port = 7860;
            guest.address = "10.0.2.15"; # …to the VM’s SLiRP IP (default 10.0.2.15)…
            guest.port = 7860;
          }
          /* {
            from = "host";
            proto = "tcp";
            host.port = 8787;
            guest.address = "10.0.2.15"; # …to the VM’s SLiRP IP (default 10.0.2.15)…
            guest.port = 8787;
          } */
        ];

        # inside-guest setup
        services.openssh.enable = true;
        services.openssh.settings.PermitRootLogin = "yes";
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

        services.static-web-server = {
          enable = true;
          root = "/var/www/";
          configuration.general = {
            directory-listing = true;
          };
        };
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
      packages = {
        inherit gradio-server exploit;
        gradio-server-vm = self.nixosConfigurations.${system}.server.config.microvm.declaredRunner;
        default = self.packages.${system}.gradio-server-vm;
      };
      apps.default = {
        type = "app";
        program = "${self.packages.${system}.gradio-server-vm}/bin/microvm-run";
      };
    });
}
