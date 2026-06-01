# happ-nixos

My attempt to get Happ running on NixOS.

This project is currently in a "works well enough for me" state. The core functionality is working, but the implementation is still far from perfect. At the moment, Hysteria2 support is not working and requires further development.

## Installation

Clone the repository into `/etc/nixos`:

```bash
cd /etc/nixos
git clone https://github.com/MrShitFox/happ-nixos
```

Import the module in your `configuration.nix`:

```nix
imports =
  [
    ./hardware-configuration.nix
    ./happ-nixos/happ-module.nix
  ];
```

Enable the service:

```nix
services.happ.enable = true;
```

Apply the configuration:

```bash
sudo nixos-rebuild switch
```

## Updating

Pull the latest changes and rebuild your system:

```bash
cd /etc/nixos/happ-nixos
git pull

sudo nixos-rebuild switch
```

## Status

* ✅ Core functionality works
* ❌ Hysteria2 is currently not working
* ⚠️ The project is still a work in progress (~~or maybe not~~)
