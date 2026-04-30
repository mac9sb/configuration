if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

source ~/.orbstack/shell/init.zsh 2>/dev/null || :
