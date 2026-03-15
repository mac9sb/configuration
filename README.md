# macOS Configuration

```sh
xcode-select --install 
mkdir -p "$HOME/Developer"
git clone https://github.com/mac9sb/configuration "$HOME/Developer/Configuration"
ln -s "$HOME/Developer/Configuration" "$HOME/.config"
echo "export ZDOTDIR=\"$HOME/.config/zsh\"" >> "$HOME/.zshenv"
sudo cp /etc/pam.d/sudo_locat.template /etc/pam.d/sudo_local
sudo sed -i '' 's/^#auth/auth/' /etc/pam.d/sudo_local
```
