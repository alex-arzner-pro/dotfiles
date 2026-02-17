#!/bin/bash
set -euo pipefail

# ============================================================
# Sway Setup Script for Ubuntu 24.04
# Profiles: personal (ThinkPad T14) / work (Dell XPS)
# Theme: Gruvbox Dark
# ============================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
skip()  { echo -e "${YELLOW}[SKIP]${NC} $1"; }

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REBOOT_NEEDED=false

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║     Sway Setup — Ubuntu 24.04            ║"
echo "║     Gruvbox Dark Theme                    ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ============================================================
# 0. Profile selection
# ============================================================
echo "Select profile:"
echo "  1) personal — ThinkPad T14 (Intel, home dock)"
echo "  2) work     — Dell XPS (Intel + NVIDIA, office dock)"
echo ""
read -p "Profile [1/2]: " PROFILE_CHOICE

case "$PROFILE_CHOICE" in
    1) PROFILE="personal" ;;
    2) PROFILE="work" ;;
    *) err "Invalid choice. Run again and select 1 or 2." ;;
esac

ok "Profile: $PROFILE"

# ============================================================
# 1. Pre-checks
# ============================================================
info "Running pre-checks..."

if [ "$EUID" -eq 0 ]; then
    err "Do not run this script as root. Run as your normal user."
fi

if ! grep -q "24.04" /etc/os-release 2>/dev/null; then
    warn "This script is designed for Ubuntu 24.04. Proceed with caution."
fi

ok "Pre-checks passed"

# ============================================================
# 2. System update
# ============================================================
info "Updating system..."

sudo apt update
sudo apt upgrade -y

ok "System updated"

# ============================================================
# 3. GPU detection and driver install
# ============================================================
info "Detecting GPU..."

GPU_INFO=$(lspci | grep -i vga || true)
echo "  $GPU_INFO"

if echo "$GPU_INFO" | grep -qi nvidia; then
    info "NVIDIA GPU detected"

    if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
        ok "NVIDIA driver already installed"
        nvidia-smi --query-gpu=name,driver_version --format=csv,noheader
    else
        info "Installing NVIDIA drivers..."
        sudo apt install -y ubuntu-drivers-common
        RECOMMENDED=$(ubuntu-drivers list 2>/dev/null | head -1)
        if [ -n "$RECOMMENDED" ]; then
            sudo ubuntu-drivers install
            ok "NVIDIA driver installed: $RECOMMENDED"
            REBOOT_NEEDED=true
        else
            warn "No NVIDIA driver found by ubuntu-drivers"
        fi
    fi
else
    ok "Intel GPU only — no additional drivers needed"
fi

if [ "$REBOOT_NEEDED" = true ]; then
    echo ""
    warn "NVIDIA driver was just installed. Reboot required."
    warn "After reboot, run this script again to continue setup."
    echo ""
    read -p "Reboot now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo reboot
    else
        info "Please reboot manually and re-run this script."
        exit 0
    fi
fi

# ============================================================
# 4. Audio check
# ============================================================
info "Checking audio..."

if pactl info &>/dev/null; then
    AUDIO_SERVER=$(pactl info 2>/dev/null | grep "Server Name" | cut -d: -f2 | xargs)
    ok "Audio server: $AUDIO_SERVER"
else
    info "Installing PulseAudio utilities..."
    sudo apt install -y pulseaudio-utils
    ok "PulseAudio utilities installed"
fi

# ============================================================
# 5. Sway and core packages
# ============================================================
info "Installing Sway and core packages..."

sudo apt install -y \
    sway swayidle swaybg swaylock waybar wl-clipboard \
    grim slurp brightnessctl playerctl \
    kitty fuzzel dunst \
    pavucontrol network-manager-gnome udiskie blueman \
    kanshi wdisplays xdg-desktop-portal-wlr \
    thunar thunar-archive-plugin tumbler \
    cliphist policykit-1-gnome \
    imv zathura \
    wtype libasound2-plugins \
    flatpak curl wget gnupg \
    gnome-keyring libsecret-1-0 \
    bash-completion

ok "Core packages installed"

# ============================================================
# 6. JetBrains Mono Nerd Font
# ============================================================
info "Installing JetBrains Mono Nerd Font..."

NERD_FONT_DIR="$HOME/.local/share/fonts/JetBrainsMonoNerd"
if [ -d "$NERD_FONT_DIR" ] && ls "$NERD_FONT_DIR"/*.ttf &>/dev/null; then
    skip "JetBrains Mono Nerd Font already installed"
else
    mkdir -p "$NERD_FONT_DIR"
    NERD_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz"
    info "Downloading from $NERD_URL..."
    wget -qO /tmp/JetBrainsMono.tar.xz "$NERD_URL"
    tar -xf /tmp/JetBrainsMono.tar.xz -C "$NERD_FONT_DIR"
    rm -f /tmp/JetBrainsMono.tar.xz
    fc-cache -f
    ok "JetBrains Mono Nerd Font installed"
fi

# ============================================================
# 7. Starship prompt
# ============================================================
info "Installing Starship..."

if command -v starship &>/dev/null; then
    skip "Starship already installed"
else
    curl -sS https://starship.rs/install.sh | sh -s -- -y
    ok "Starship installed"
fi

if ! grep -q "starship init bash" ~/.bashrc 2>/dev/null; then
    echo 'eval "$(starship init bash)"' >> ~/.bashrc
    ok "Starship added to bashrc"
else
    skip "Starship already in bashrc"
fi

# ============================================================
# 8. Flatpak setup
# ============================================================
info "Setting up Flatpak..."

if ! flatpak remote-list | grep -q flathub; then
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    ok "Flathub added"
else
    skip "Flathub already configured"
fi

# ============================================================
# 9. Google Chrome
# ============================================================
info "Installing Google Chrome..."

if command -v google-chrome &>/dev/null; then
    skip "Chrome already installed"
else
    wget -qO /tmp/chrome.deb "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
    sudo dpkg -i /tmp/chrome.deb || sudo apt install -f -y
    rm -f /tmp/chrome.deb
    ok "Chrome installed"
fi

# ============================================================
# 10. Messaging apps (Flatpak)
# ============================================================
info "Installing messaging apps..."

FLATPAK_APPS=(
    "org.signal.Signal"
    "com.slack.Slack"
    "org.telegram.desktop"
)

for APP in "${FLATPAK_APPS[@]}"; do
    if flatpak list --app | grep -q "$APP"; then
        skip "$APP already installed"
    else
        info "Installing $APP..."
        flatpak install -y flathub "$APP"
        ok "$APP installed"
    fi
done

# ============================================================
# 11. Handy (voice input) — latest release from GitHub
# ============================================================
info "Installing Handy..."

if command -v handy &>/dev/null; then
    INSTALLED_VER=$(handy --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
    LATEST_VER=$(curl -sL https://api.github.com/repos/cjpais/Handy/releases/latest | grep -oP '"tag_name":\s*"v?\K[^"]+')
    if [ "$INSTALLED_VER" = "$LATEST_VER" ]; then
        skip "Handy already at latest version ($INSTALLED_VER)"
    else
        info "Updating Handy: $INSTALLED_VER → $LATEST_VER"
        wget -qO /tmp/handy.deb "https://github.com/cjpais/Handy/releases/latest/download/Handy_${LATEST_VER}_amd64.deb"
        sudo dpkg -i /tmp/handy.deb || sudo apt install -f -y
        rm -f /tmp/handy.deb
        ok "Handy updated to $LATEST_VER"
    fi
else
    LATEST_VER=$(curl -sL https://api.github.com/repos/cjpais/Handy/releases/latest | grep -oP '"tag_name":\s*"v?\K[^"]+')
    if [ -z "$LATEST_VER" ]; then
        warn "Could not fetch latest Handy version from GitHub"
    else
        info "Installing Handy $LATEST_VER..."
        wget -qO /tmp/handy.deb "https://github.com/cjpais/Handy/releases/latest/download/Handy_${LATEST_VER}_amd64.deb"
        sudo dpkg -i /tmp/handy.deb || sudo apt install -f -y
        rm -f /tmp/handy.deb
        ok "Handy $LATEST_VER installed"
    fi
fi

# ============================================================
# 12. Create directories
# ============================================================
info "Creating directories..."

mkdir -p ~/.config/{sway,sway/config.d,kitty,fuzzel,dunst,waybar,kanshi,starship}
mkdir -p ~/bin
mkdir -p ~/Pictures

ok "Directories created"

# ============================================================
# 13. Deploy configs from dotfiles
# ============================================================
info "Deploying configs..."

cp "$DOTFILES_DIR/config/sway/config"          ~/.config/sway/config
cp "$DOTFILES_DIR/config/kitty/kitty.conf"      ~/.config/kitty/kitty.conf
cp "$DOTFILES_DIR/config/waybar/config"         ~/.config/waybar/config
cp "$DOTFILES_DIR/config/waybar/style.css"      ~/.config/waybar/style.css
cp "$DOTFILES_DIR/config/fuzzel/fuzzel.ini"     ~/.config/fuzzel/fuzzel.ini
cp "$DOTFILES_DIR/config/dunst/dunstrc"         ~/.config/dunst/dunstrc
cp "$DOTFILES_DIR/config/starship.toml"         ~/.config/starship.toml
cp "$DOTFILES_DIR/config/electron-flags.conf"   ~/.config/electron-flags.conf

ok "Configs deployed"

# ============================================================
# 14. Deploy profile-specific configs (monitors, kanshi)
# ============================================================
info "Deploying profile configs: $PROFILE..."

cp "$DOTFILES_DIR/profiles/$PROFILE/monitors.conf"  ~/.config/sway/config.d/monitors.conf
cp "$DOTFILES_DIR/profiles/$PROFILE/kanshi.config"   ~/.config/kanshi/config

ok "Profile configs deployed ($PROFILE)"

# ============================================================
# 15. Handy settings
# ============================================================
info "Deploying Handy settings..."

HANDY_SETTINGS_DIR="$HOME/.local/share/com.pais.handy"
mkdir -p "$HANDY_SETTINGS_DIR"
cp "$DOTFILES_DIR/config/handy/settings_store.json" "$HANDY_SETTINGS_DIR/settings_store.json"

ok "Handy settings deployed"

# ============================================================
# 16. Gnome Keyring (bashrc)
# ============================================================
info "Configuring gnome-keyring..."

if ! grep -q "gnome-keyring-daemon" ~/.bashrc 2>/dev/null; then
    cat >> ~/.bashrc << 'KEYRING_EOF'

# Gnome Keyring (secrets, ssh agent)
if [ -z "$GNOME_KEYRING_CONTROL" ]; then
    eval $(gnome-keyring-daemon --start --components=secrets,pkcs11,ssh 2>/dev/null)
    export GNOME_KEYRING_CONTROL
    export SSH_AUTH_SOCK
fi
KEYRING_EOF
    ok "gnome-keyring added to bashrc"
else
    skip "gnome-keyring already in bashrc"
fi

# ============================================================
# 17. GTK dark theme
# ============================================================
info "Applying dark theme..."

gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true

ok "Dark theme applied"

# ============================================================
# 18. Flatpak desktop integration
# ============================================================
info "Configuring Flatpak desktop integration..."

sudo flatpak override --filesystem=~/.local/share/icons:ro 2>/dev/null || true
sudo flatpak override --filesystem=~/.local/share/themes:ro 2>/dev/null || true

ok "Flatpak integration configured"

# ============================================================
# Summary
# ============================================================
_w=42
_top() { printf "╔"; printf '═%.0s' $(seq 1 $_w); printf "╗\n"; }
_mid() { printf "╠"; printf '═%.0s' $(seq 1 $_w); printf "╣\n"; }
_bot() { printf "╚"; printf '═%.0s' $(seq 1 $_w); printf "╝\n"; }
_line() { printf "║  %-$((_w - 2))s║\n" "$1"; }
_empty() { printf "║%${_w}s║\n" ""; }

echo ""
_top
_line "Setup complete!"
_line "Profile: $PROFILE"
_line "Theme: Gruvbox Dark"
_mid
_empty
_line "1. Log out"
_line "2. Select 'Sway' on the login screen"
_line "3. Log in"
_empty
_line "Key bindings:"
_line "  Super+Enter    - terminal"
_line "  Super+d        - launcher"
_line "  Super+Shift+q  - close window"
_line "  Super+1-9      - workspaces"
_line "  Super+Shift+p  - power menu"
_line "  Super+Escape   - lock screen"
_line "  Ctrl+Space     - Handy transcribe"
_line "  CapsLock       - switch DE/RU"
_line "  Super+c        - clipboard history"
_line "  Super+t        - file manager"
_empty
_line "Installed:"
_line "  Chrome, Signal, Slack, Telegram"
_line "  Handy, Starship, Nerd Fonts"
_empty
if [ "$PROFILE" = "work" ]; then
_line "NOTE: Edit monitors after login:"
_line "  swaymsg -t get_outputs"
_line "  ~/.config/sway/config.d/monitors.conf"
_line "  ~/.config/kanshi/config"
_empty
fi
_bot
echo ""
