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
PROFILE_FILE="$HOME/.config/dotfiles-profile"

if [ -f "$PROFILE_FILE" ]; then
    PROFILE=$(cat "$PROFILE_FILE")
    if [ "$PROFILE" = "personal" ] || [ "$PROFILE" = "work" ]; then
        ok "Profile: $PROFILE (saved)"
        read -p "Change profile? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -f "$PROFILE_FILE"
        fi
    else
        warn "Invalid saved profile, re-selecting..."
        rm -f "$PROFILE_FILE"
    fi
fi

if [ ! -f "$PROFILE_FILE" ]; then
    echo "Select profile:"
    echo "  1) personal — ThinkPad T14 (Intel, home dock)"
    echo "  2) work     — Dell XPS (Intel + NVIDIA, office dock)"
    echo ""
    read -r -p "Profile [1/2]: " PROFILE_CHOICE

    case "$PROFILE_CHOICE" in
        1) PROFILE="personal" ;;
        2) PROFILE="work" ;;
        *) err "Invalid choice. Run again and select 1 or 2." ;;
    esac

    mkdir -p "$(dirname "$PROFILE_FILE")"
    echo "$PROFILE" > "$PROFILE_FILE"
    ok "Profile: $PROFILE (saved to $PROFILE_FILE)"
fi

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

GPU_INFO=$(lspci | grep -iE 'vga|3d controller' || true)
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
    # PRIME profile and PowerMizer performance mode (work profile)
    if [ "$PROFILE" = "work" ]; then
        if command -v prime-select &>/dev/null; then
            CURRENT_PRIME=$(prime-select query 2>/dev/null || echo "unknown")
            if [ "$CURRENT_PRIME" != "nvidia" ]; then
                info "Setting PRIME profile to nvidia..."
                sudo prime-select nvidia
                ok "PRIME profile set to nvidia"
                REBOOT_NEEDED=true
            else
                skip "PRIME profile already set to nvidia"
            fi
        fi

        NVPM_CONF="/etc/modprobe.d/nvidia-powermizer.conf"
        NVPM_LINE='options nvidia NVreg_RegistryDwords="PowerMizerEnable=0x1;PerfLevelSrc=0x2222;PowerMizerDefault=0x3;PowerMizerDefaultAC=0x3"'
        if [ -f "$NVPM_CONF" ] && grep -qF "$NVPM_LINE" "$NVPM_CONF"; then
            skip "PowerMizer already set to maximum performance"
        else
            echo "$NVPM_LINE" | sudo tee "$NVPM_CONF" > /dev/null
            ok "PowerMizer set to maximum performance"
        fi

        # Sway needs --unsupported-gpu flag with proprietary NVIDIA drivers
        SWAY_DESKTOP="/usr/share/wayland-sessions/sway.desktop"
        if [ -f "$SWAY_DESKTOP" ]; then
            if grep -q '\-\-unsupported-gpu' "$SWAY_DESKTOP"; then
                skip "Sway already configured for NVIDIA (--unsupported-gpu)"
            else
                sudo sed -i 's|Exec=sway|Exec=sway --unsupported-gpu|' "$SWAY_DESKTOP"
                ok "Sway configured for NVIDIA (--unsupported-gpu)"
            fi
        fi
    fi
else
    ok "Intel GPU only — no additional drivers needed"
fi

if [ "$REBOOT_NEEDED" = true ]; then
    echo ""
    warn "NVIDIA configuration changed. Reboot required."
    warn "After reboot, run this script again to continue setup."
    echo ""
    read -p "Reboot now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo reboot
        exit 0
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
# 5. SSH server and reboot protection (work profile)
# ============================================================
if [ "$PROFILE" = "work" ]; then
    info "Setting up SSH server..."

    if dpkg -l openssh-server 2>/dev/null | grep -q '^ii'; then
        skip "openssh-server already installed"
    else
        sudo apt install -y openssh-server
        ok "openssh-server installed"
    fi

    if systemctl is-enabled ssh &>/dev/null && systemctl is-active ssh &>/dev/null; then
        skip "SSH server already enabled and running"
    else
        sudo systemctl enable ssh &>/dev/null
        sudo systemctl start ssh
        ok "SSH server enabled and running"
    fi

    # molly-guard: asks hostname confirmation before shutdown/reboot over SSH
    info "Setting up reboot protection..."
    if dpkg -l molly-guard 2>/dev/null | grep -q '^ii'; then
        skip "molly-guard already installed"
    else
        sudo apt install -y molly-guard
        ok "molly-guard installed"
    fi

    # Power management: disable power button, lid suspend, idle suspend
    LOGIND_OVERRIDE="/etc/systemd/logind.conf.d/power-management.conf"
    if [ -f "$LOGIND_OVERRIDE" ] && grep -q "HandleLidSwitch=ignore" "$LOGIND_OVERRIDE"; then
        skip "Power management already configured"
    else
        sudo mkdir -p /etc/systemd/logind.conf.d
        sudo rm -f /etc/systemd/logind.conf.d/power-button.conf
        printf '[Login]\nHandlePowerKey=ignore\nHandlePowerKeyLongPress=poweroff\nHandleLidSwitch=ignore\nHandleLidSwitchExternalPower=ignore\nHandleLidSwitchDocked=ignore\nIdleAction=ignore\n' \
            | sudo tee "$LOGIND_OVERRIDE" > /dev/null
        sudo systemctl restart systemd-logind &>/dev/null || true
        ok "Power management configured (no suspend on lid close/idle)"
    fi

    # Mask sleep targets to completely prevent suspend/hibernate
    if systemctl is-enabled suspend.target 2>/dev/null | grep -q "masked"; then
        skip "Sleep targets already masked"
    else
        sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
        ok "Sleep targets masked (suspend/hibernate disabled)"
    fi
else
    skip "SSH server / reboot protection — skipped (personal profile)"
fi

# ============================================================
# 6. Sway and core packages
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
# 6a. Default applications
# ============================================================
info "Setting default applications..."

# Terminal emulator → Kitty
if update-alternatives --query x-terminal-emulator 2>/dev/null | grep -q "Value:.*kitty"; then
    skip "Kitty already set as default terminal"
else
    sudo update-alternatives --set x-terminal-emulator /usr/bin/kitty 2>/dev/null \
        || sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/kitty 50 \
        && sudo update-alternatives --set x-terminal-emulator /usr/bin/kitty
    ok "Kitty set as default terminal"
fi

# Web browser → Chrome
if xdg-settings get default-web-browser 2>/dev/null | grep -q "google-chrome"; then
    skip "Chrome already set as default browser"
else
    xdg-settings set default-web-browser google-chrome.desktop 2>/dev/null
    ok "Chrome set as default browser"
fi

# File manager → Thunar
if xdg-mime query default inode/directory 2>/dev/null | grep -q "thunar"; then
    skip "Thunar already set as default file manager"
else
    xdg-mime default thunar.desktop inode/directory
    ok "Thunar set as default file manager"
fi

# XFCE helpers (Thunar uses exo-open, not x-terminal-emulator)
XFCE_HELPERS="$HOME/.config/xfce4/helpers.rc"
if [ -f "$XFCE_HELPERS" ] && grep -q "TerminalEmulator=custom" "$XFCE_HELPERS"; then
    skip "XFCE helpers already configured"
else
    mkdir -p "$HOME/.config/xfce4"
    cat > "$XFCE_HELPERS" << 'EOF'
TerminalEmulator=custom-TerminalEmulator
TerminalEmulatorCustom=kitty
WebBrowser=custom-WebBrowser
WebBrowserCustom=google-chrome-stable
FileManager=custom-FileManager
FileManagerCustom=thunar
EOF
    ok "XFCE helpers configured (Thunar terminal → Kitty)"
fi

# ============================================================
# 6b. Brightnessctl permissions
# ============================================================
info "Configuring brightnessctl permissions..."

UDEV_BACKLIGHT="/etc/udev/rules.d/90-backlight.rules"
UDEV_RULE='ACTION=="add", SUBSYSTEM=="backlight", RUN+="/bin/chgrp video /sys/class/backlight/%k/brightness", RUN+="/bin/chmod g+w /sys/class/backlight/%k/brightness"'
if [ -f "$UDEV_BACKLIGHT" ] && grep -qF 'SUBSYSTEM=="backlight"' "$UDEV_BACKLIGHT"; then
    skip "Backlight udev rule already configured"
else
    echo "$UDEV_RULE" | sudo tee "$UDEV_BACKLIGHT" > /dev/null
    sudo udevadm control --reload-rules
    sudo udevadm trigger --subsystem-match=backlight
    ok "Backlight udev rule installed"
fi

if id -nG "$USER" | grep -qw video; then
    skip "User already in video group"
else
    sudo usermod -aG video "$USER"
    ok "User added to video group"
    echo ""
    warn "Group membership changed. Re-login required."
    warn "After re-login, run this script again to continue setup."
    echo ""
    read -p "Log out now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        loginctl terminate-user "$USER"
        exit 0
    else
        info "Please log out manually and re-run this script."
        exit 0
    fi
fi

# ============================================================
# 7. JetBrains Mono Nerd Font
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
# 9a. VS Code
# ============================================================
info "Installing VS Code..."

if command -v code &>/dev/null; then
    skip "VS Code already installed"
else
    wget -qO /tmp/vscode.deb "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
    sudo dpkg -i /tmp/vscode.deb || sudo apt install -f -y
    rm -f /tmp/vscode.deb
    ok "VS Code installed"
fi

# ============================================================
# 9b. Google Antigravity IDE
# ============================================================
info "Installing Antigravity..."

if command -v antigravity &>/dev/null; then
    skip "Antigravity already installed"
else
    AGY_KEYRING="/usr/share/keyrings/google-antigravity.gpg"
    AGY_REPO="/etc/apt/sources.list.d/google-antigravity.list"
    if [ ! -f "$AGY_KEYRING" ]; then
        curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg \
            | sudo gpg --batch --yes --dearmor -o "$AGY_KEYRING"
    fi
    if [ ! -f "$AGY_REPO" ]; then
        echo "deb [arch=amd64 signed-by=$AGY_KEYRING] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev antigravity-debian main" \
            | sudo tee "$AGY_REPO" > /dev/null
        sudo apt update
    fi
    sudo apt install -y antigravity
    ok "Antigravity installed"
fi

# ============================================================
# 9c. Nextcloud client (via official PPA)
# ============================================================
info "Installing Nextcloud client..."

if command -v nextcloud &>/dev/null; then
    skip "Nextcloud client already installed"
else
    if ! grep -rq "nextcloud-devs/client" /etc/apt/sources.list.d/ 2>/dev/null; then
        sudo add-apt-repository -y ppa:nextcloud-devs/client
        sudo apt update
    fi
    sudo apt install -y nextcloud-desktop
    ok "Nextcloud client installed"
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
    INSTALLED_VER=$(dpkg-query -W -f='${Version}' handy 2>/dev/null || echo "unknown")
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
# 11a. Ventoy (bootable USB tool)
# ============================================================
info "Installing Ventoy..."

VENTOY_DIR="$HOME/bin/ventoy"
if [ -d "$VENTOY_DIR" ] && [ -f "$VENTOY_DIR/Ventoy2Disk.sh" ]; then
    skip "Ventoy already installed in $VENTOY_DIR"
else
    VENTOY_VER=$(curl -sL https://api.github.com/repos/ventoy/Ventoy/releases/latest | grep -oP '"tag_name":\s*"v?\K[^"]+')
    if [ -z "$VENTOY_VER" ]; then
        warn "Could not fetch latest Ventoy version from GitHub"
    else
        info "Downloading Ventoy $VENTOY_VER..."
        wget -qO /tmp/ventoy.tar.gz "https://github.com/ventoy/Ventoy/releases/download/v${VENTOY_VER}/ventoy-${VENTOY_VER}-linux.tar.gz"
        mkdir -p "$VENTOY_DIR"
        tar -xzf /tmp/ventoy.tar.gz -C /tmp
        cp -r "/tmp/ventoy-${VENTOY_VER}/"* "$VENTOY_DIR"/
        rm -rf /tmp/ventoy.tar.gz "/tmp/ventoy-${VENTOY_VER}"
        ok "Ventoy $VENTOY_VER installed in $VENTOY_DIR"
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
cp "$DOTFILES_DIR/config/ventoy-web.sh"         ~/bin/ventoy-web.sh
chmod +x ~/bin/ventoy-web.sh
mkdir -p ~/.local/share/applications
sed "s|HOMEDIR|$HOME|g" "$DOTFILES_DIR/config/ventoy.desktop" > ~/.local/share/applications/ventoy.desktop
ok "Configs deployed"

# ============================================================
# 13a. User avatar (GDM / AccountsService)
# ============================================================
info "Setting user avatar..."

cp "$DOTFILES_DIR/config/face.jpg" ~/.face
ACCT_ICON="/var/lib/AccountsService/icons/$USER"
ACCT_USER="/var/lib/AccountsService/users/$USER"
sudo cp "$DOTFILES_DIR/config/face.jpg" "$ACCT_ICON"
if [ -f "$ACCT_USER" ]; then
    if grep -q "^Icon=" "$ACCT_USER"; then
        sudo sed -i "s|^Icon=.*|Icon=$ACCT_ICON|" "$ACCT_USER"
    else
        echo "Icon=$ACCT_ICON" | sudo tee -a "$ACCT_USER" > /dev/null
    fi
else
    printf '[User]\nIcon=%s\n' "$ACCT_ICON" | sudo tee "$ACCT_USER" > /dev/null
fi

ok "User avatar set"

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
# 19. Cleanup
# ============================================================
info "Cleaning up unused packages..."

sudo apt autoremove -y
sudo apt autoclean -y

ok "Cleanup complete"

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
_line "  Chrome, VS Code, Antigravity"
_line "  Nextcloud client"
_line "  Signal, Slack, Telegram"
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
