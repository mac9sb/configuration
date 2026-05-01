# macOS Configuration

## Quickstart

```sh
./scripts/install.sh
```

## Uninstall

```sh
"$HOME/Developer/configuration/scripts/uninstall.sh"
```

To also remove the cloned repository itself:

```sh
REMOVE_REPO=1 "$HOME/Developer/configuration/scripts/uninstall.sh"
```

## Benchmarking Shell Startup

Profile shell startup with the built-in `zprof` support:

```sh
ZSHRC_PROFILE=1 zsh -i -c exit
```
