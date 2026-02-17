# dotfiles

Sway + Gruvbox Dark environment for Ubuntu 24.04 (minimal install).

## Quick start

1. Install Ubuntu Desktop (minimal installation)

2. Install git and clone:

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/alex-arzner-pro/dotfiles.git ~/dotfiles
```

1. Run setup:

```bash
cd ~/dotfiles
./setup.sh
```

The script will ask to choose a profile:

- **personal** — ThinkPad T14 (Intel, home dock)
- **work** — Dell XPS (Intel + NVIDIA, office dock)

1. Log out, select **Sway** on the login screen, log in.

## What gets installed

- **WM**: Sway, Waybar, Kanshi, Swaylock, Swayidle
- **Terminal**: Kitty + JetBrains Mono Nerd Font + Starship prompt
- **Apps**: Chrome, Signal, Slack, Telegram, Handy (voice input)
- **Utilities**: Fuzzel, Dunst, Cliphist, Thunar, Grim/Slurp, Brightnessctl

## Structure

```text
dotfiles/
├── setup.sh              # main entry point
├── config/
│   ├── sway/config       # sway config
│   ├── kitty/kitty.conf
│   ├── waybar/           # config + style.css
│   ├── fuzzel/fuzzel.ini
│   ├── dunst/dunstrc
│   ├── handy/            # voice input settings
│   ├── starship.toml
│   └── electron-flags.conf
└── profiles/
    ├── personal/         # ThinkPad T14 (monitors, kanshi)
    └── work/             # Dell XPS (monitors, kanshi)
```
