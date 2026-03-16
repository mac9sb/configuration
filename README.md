# macOS Configuration

## Quickstart

```sh
# Install Xcode Command Line Tools
xcode-select --install

# Clone configuration repository
mkdir -p "$HOME/Developer"
git clone --single-branch https://github.com/mac9sb/configuration "$HOME/Developer/Configuration"

# Symlink individual config folders into ~/.config
mkdir -p "$HOME/.config"
for dir in atuin git mise ssh vim zed zsh; do
    target="$HOME/.config/$dir"
    [ -e "$target" ] && mv "$target" "$target.bak"
    ln -s "$HOME/Developer/Configuration/$dir" "$target"
done

# Ensure ZDOTDIR is set in .zshenv so zsh finds config on every shell start
[ -f "$HOME/.zshenv" ] && cp "$HOME/.zshenv" "$HOME/.zshenv.bak"
grep -q ZDOTDIR "$HOME/.zshenv" 2>/dev/null ||
    echo "export ZDOTDIR=\"$HOME/.config/zsh\"" >> "$HOME/.zshenv"

# Generate SSH key (skipped if one already exists) and link config
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    ssh-keygen -t ed25519 -C "maclong9@icloud.com"
fi
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
for dir in atuin git mise ssh vim zed zsh; do
    rm "$HOME/.config/$dir"
done
rm "$HOME/.ssh/config"

# Restore backups
for dir in atuin git mise ssh vim zed zsh; do
    [ -e "$HOME/.config/$dir.bak" ] && mv "$HOME/.config/$dir.bak" "$HOME/.config/$dir"
done
[ -f "$HOME/.zshenv.bak" ] && mv "$HOME/.zshenv.bak" "$HOME/.zshenv" ||
    sed -i '' '/ZDOTDIR/d' "$HOME/.zshenv"

# Revert TouchID for `sudo`
sudo rm /etc/pam.d/sudo_local

# Remove cloned repository
rm -rf "$HOME/Developer/Configuration"
```

## Benchmarking Shell Startup

To measure zsh startup time, run:

```sh
# Quick benchmark (10 iterations)
for i in $(seq 1 10); do /usr/bin/time zsh -i -c exit 2>&1; done

# Detailed profiling (add to top of .zshrc, then open a new shell)
# zmodload zsh/zprof
# ... (at the bottom of .zshrc, add:)
# zprof
```

You can also enable the built-in `zprof` support by setting `ZSHRC_PROFILE=1` before launching a shell:

```sh
ZSHRC_PROFILE=1 zsh -i -c exit
```
