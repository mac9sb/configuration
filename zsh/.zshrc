export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
setopt auto_cd correct histignorealldups interactive_comments sharehistory

eval "$(/opt/homebrew/bin/brew shellenv)"

# Aliases
alias cat="bat"
alias bcat="/bin/cat"

# Completions
FPATH="$(brew --prefix)/share/zsh/site-functions:$FPATH"
autoload -Uz compinit && compinit

# Plugins
source "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
source "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
source "$(brew --prefix)/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh"

# Keybinds
bindkey -M emacs \
    "^[p"   .history-search-backward \
    "^[n"   .history-search-forward \
    "^P"    .up-line-or-history \
    "^[OA"  .up-line-or-history \
    "^[[A"  .up-line-or-history \
    "^N"    .down-line-or-history \
    "^[OB"  .down-line-or-history \
    "^[[B"  .down-line-or-history \
    "^R"    .history-incremental-search-backward \
    "^S"    .history-incremental-search-forward

eval "$(starship init zsh)"
