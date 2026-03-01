export PATH="$HOME/.local/bin/:$PATH"
setopt auto_cd correct histignorealldups interactive_comments sharehistory
eval "$(/opt/homebrew/bin/brew shellenv)"
eval "$(starship init zsh)"
