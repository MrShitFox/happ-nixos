{ config, pkgs, lib, ... }:

let
  inherit (lib) mkIf mkEnableOption mkOption types stringAfter;
  cfg = config.services.happ;
in
{
  options.services.happ = {
    enable = mkEnableOption "Happ proxy desktop client and background TUN daemon";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./happ.nix { inherit (cfg) forceXwayland forceSoftwareRendering; };
      defaultText = "pkgs.callPackage ./happ.nix { }";
      description = "The Happ package to use.";
    };

    forceXwayland = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Force Happ to run through XWayland (XCB) instead of its bundled Qt6
        Wayland plugins, which are dropped from the package entirely. Works
        around a silent startup crash on wlroots-based Wayland compositors
        (Hyprland, Sway, ...) where the bundled Qt6 Wayland integration is
        incompatible. Only affects the default `package` build above; has
        no effect if you override `services.happ.package` yourself.
      '';
    };

    forceSoftwareRendering = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Force Happ's Qt Quick UI to render in software (`QML_SCENE_GRAPH=software`,
        `LIBGL_ALWAYS_SOFTWARE=1`). Independent of `forceXwayland` -- use this if
        Happ's UI renders incorrectly or not at all due to a GPU/driver issue,
        regardless of which Qt platform backend is in use. Only affects the
        default `package` build above; has no effect if you override
        `services.happ.package` yourself.
      '';
    };

    tunInterface = mkOption {
      type = types.str;
      default = "tun0";
      description = ''
        Name of the TUN interface Happ brings up; it is added to the firewall's
        trusted interfaces so tunnelled traffic is not dropped.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Tools Happ and its helper scripts call from the system PATH.
    environment.systemPackages = [
      cfg.package
      pkgs.net-tools
      pkgs.lsb-release
    ];

    # HWID fix. Happ reads its hardware id from Qt's QSysInfo::machineUniqueId(),
    # which on Linux comes from /var/lib/dbus/machine-id. NixOS defaults to
    # dbus-broker, which (unlike the classic dbus-daemon) does not create that
    # file, so the id is empty and the client shows a blank HWID. Linking it to
    # the real /etc/machine-id fixes it.
    #
    # Note: keep happd (below) unsandboxed. systemd sandboxing (ProtectSystem,
    # PrivateTmp, ...) enables a mount namespace whose machine-id bind-mount fails
    # here with 226/NAMESPACE and breaks TUN mode.
    systemd.tmpfiles.rules = [
      "L+ /var/lib/dbus/machine-id - - - - /etc/machine-id"
    ];

    # Firewall + TUN module for Happ's TUN mode.
    networking.firewall.checkReversePath = "loose";
    networking.firewall.trustedInterfaces = [ cfg.tunInterface ];
    boot.kernelModules = [ "tun" ];

    # Happ hard-codes /opt/happ for its binaries, so we materialise the immutable
    # Nix store tree there. The copy runs only when the package changes, keeping
    # everyday rebuilds fast. Happ's actual runtime state (routing, generated core
    # configs) lives per-user under ~/.config/Happ, not under /opt/happ, so the
    # materialised tree only needs to be readable/executable, never writable --
    # making it world-writable would let any unprivileged local user replace the
    # happd binary that systemd runs as root below.
    system.activationScripts.happ-opt = stringAfter [ "stdio" ] ''
      stamp=/opt/happ/.nix-store-path
      if [ "$(cat "$stamp" 2>/dev/null)" != "${cfg.package}" ]; then
        rm -rf /opt/happ
        mkdir -p /opt/happ
        cp -r ${cfg.package}/happ/. /opt/happ/
        chown -R root:root /opt/happ
        chmod -R u=rwX,go=rX /opt/happ
        printf '%s' "${cfg.package}" > "$stamp"
      fi
    '';

    # Privileged daemon that runs the TUN cores (sing-box / tun2proxy) as root.
    systemd.services.happd = {
      description = "Happ Process Control Daemon";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      # ExecStart is a fixed /opt/happ path rather than a Nix store path, so
      # switch-to-configuration can't see a package bump from the unit alone;
      # without this, happd would keep running the old binary after an upgrade.
      restartTriggers = [ cfg.package ];

      path = with pkgs; [ iproute2 iptables procps net-tools ];

      serviceConfig = {
        Type = "simple";
        User = "root";
        Group = "root";
        ExecStart = "/opt/happ/bin/happd";
        Restart = "on-failure";
        RestartSec = "5s";
        TimeoutStopSec = "10s";
        KillMode = "mixed";
        KillSignal = "SIGTERM";
      };
    };
  };
}
