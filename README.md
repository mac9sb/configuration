# macOS Configuration

```sh
# Install Xcode Command Line Tools
xcode-select --install 
# Clone, Link & Initialise Configuration Files
mkdir -p "$HOME/Developer"
git clone https://github.com/mac9sb/configuration "$HOME/Developer/Configuration"
ln -s "$HOME/Developer/Configuration" "$HOME/.config"
echo "export ZDOTDIR=\"$HOME/.config/zsh\"" >> "$HOME/.zshenv"
# Enable TouchID for `sudo`
sudo cp /etc/pam.d/sudo_local.template /etc/pam.d/sudo_local
sudo sed -i '' 's/^#auth/auth/' /etc/pam.d/sudo_local
```

> [!NOTE]
> You can easily install this on non-macOS UNIX-based systems by removing the Xcode and TouchID lines.
