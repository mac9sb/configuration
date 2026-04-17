# macOS Configuration

## Quickstart

```sh
curl -fsSL https://raw.githubusercontent.com/mac9sb/configuration/main/scripts/install.sh | sh
```

## Uninstall

```sh
"$HOME/Developer/configuration/scripts/uninstall.sh"
```

## Benchmarking Shell Startup

Profile shell startup with the built-in `zprof` support:

```sh
ZSHRC_PROFILE=1 zsh -i -c exit
```
