# Profiling
[[ "$ZSHRC_PROFILE" == "1" ]] && zmodload zsh/zprof

# Options
setopt auto_cd correct interactive_comments
bindkey -e

# History
HISTFILE="${ZDOTDIR:-$HOME}/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt appendhistory sharehistory \
       hist_ignore_space hist_ignore_all_dups hist_save_no_dups hist_ignore_dups
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward

# Environment
export EDITOR=nvim
export VISUAL=zed

# Zinit bootstrap
ZINIT_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"
if [[ ! -d $ZINIT_HOME/.git ]]; then
  mkdir -p ${ZINIT_HOME:h}
  git clone --depth=1 https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi
source "$ZINIT_HOME/zinit.zsh"

# Plugins
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-syntax-highlighting
zinit light Aloxaf/fzf-tab

zinit ice atload'ZSH_AUTOSUGGEST_STRATEGY=(history)'
zinit light zsh-users/zsh-autosuggestions

# Completion
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':completion:*' verbose yes
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'

autoload -Uz compinit
if [[ ! -f "${ZDOTDIR:-$HOME}/.zcompdump" ]] || \
   [[ $(( $(date +%s) - $(date -r "${ZDOTDIR:-$HOME}/.zcompdump" +%s) )) -gt 86400 ]]; then
  compinit
else
  compinit -C
fi

# Compile zshrc for faster loading
setopt promptsubst
if [[ ! -f "${ZDOTDIR:-$HOME}/.zshrc.zwc" ]] || \
   [[ "${ZDOTDIR:-$HOME}/.zshrc" -nt "${ZDOTDIR:-$HOME}/.zshrc.zwc" ]]; then
  zcompile "${ZDOTDIR:-$HOME}/.zshrc" 2>/dev/null
fi

# mise (activates managed tools onto PATH)
eval "$(mise activate zsh)"

# Shell integrations
eval "$(fzf --zsh)"
eval "$(zoxide init zsh)"

# Prompt
eval "$(oh-my-posh init zsh --config ${ZDOTDIR:-$HOME/.config/zsh}/omp.toml)"
autoload -Uz add-zsh-hook
_omp_prompt_newline() { print "" }
add-zsh-hook precmd _omp_prompt_newline

# Local overrides
[[ -f ${ZDOTDIR:-$HOME}/.zshrc.local ]] && source ${ZDOTDIR:-$HOME}/.zshrc.local

# Profiling output
[[ "$ZSHRC_PROFILE" == "1" ]] && zprof
