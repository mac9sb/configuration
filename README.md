# macOS Configuration

## Quickstart

```sh
# Install Xcode Command Line Tools
xcode-select --install

# Clone, Link & Initialise Configuration Files
mkdir -p "$HOME/Developer"
git clone https://github.com/mac9sb/configuration "$HOME/Developer/Configuration"

# Back up and replace existing .config if present
[ -e "$HOME/.config" ] && mv "$HOME/.config" "$HOME/.config.bak"
ln -s "$HOME/Developer/Configuration" "$HOME/.config"

# Ensure ZDOTDIR is set in .zshenv so zsh finds config on every shell start
[ -f "$HOME/.zshenv" ] && cp "$HOME/.zshenv" "$HOME/.zshenv.bak"
grep -q ZDOTDIR "$HOME/.zshenv" 2>/dev/null ||
    echo "export ZDOTDIR=\"$HOME/.config/zsh\"" >> "$HOME/.zshenv"
    
# Generate SSH key and link config
ssh-keygen -t ed25519 -C "maclong9@icloud.com"
mkdir -p "$HOME/.ssh" && ln -sf "$HOME/.config/ssh/config" "$HOME/.ssh/config"

# Enable TouchID for `sudo`
sudo cp /etc/pam.d/sudo_local.template /etc/pam.d/sudo_local
sudo sed -i '' 's/^#auth/auth/' /etc/pam.d/sudo_local
```

> [!TIP]
> You can easily install this on non-macOS UNIX-based systems by removing the Xcode and TouchID lines.

## Uninstall

```sh
# Remove symlinks
rm "$HOME/.config"
rm "$HOME/.ssh/config"

# Restore backups
[ -e "$HOME/.config.bak" ] && mv "$HOME/.config.bak" "$HOME/.config"
[ -f "$HOME/.zshenv.bak" ] && mv "$HOME/.zshenv.bak" "$HOME/.zshenv" ||
    sed -i '' '/ZDOTDIR/d' "$HOME/.zshenv"
    
# Revert TouchID for `sudo`
sudo rm /etc/pam.d/sudo_local

# Remove cloned repository
rm -rf "$HOME/Developer/Configuration"
```
