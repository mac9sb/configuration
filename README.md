# macOS Configuration

```sh
mkdir -p "$HOME/Developer"
git clone https://github.com/mac9sb/configuration "$HOME/Developer/configuration"
ln -s "$HOME/Developer/configuration" "$HOME/.config"
echo "export ZDOTDIR=\"$HOME/.config/zsh\"" >> "$HOME/.zshenv"
```
