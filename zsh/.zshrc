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

zinit ice wait"0" lucid atload"ZSH_AUTOSUGGEST_STRATEGY=(history)"
zinit light zsh-users/zsh-autosuggestions

# Completion
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':completion:*' verbose yes
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'

zmodload -F zsh/stat b:zstat 2>/dev/null
autoload -Uz compinit
{
  local _zdump="${ZDOTDIR:-$HOME}/.zcompdump" _mtime=0
  zstat -A _mtime +mtime "$_zdump" 2>/dev/null
  if (( EPOCHSECONDS - _mtime > 86400 )); then
    compinit
  else
    compinit -C
  fi
}

# Compile zshrc for faster loading
if [[ ! -f "${ZDOTDIR:-$HOME}/.zshrc.zwc" ]] || \
   [[ "${ZDOTDIR:-$HOME}/.zshrc" -nt "${ZDOTDIR:-$HOME}/.zshrc.zwc" ]]; then
  zcompile "${ZDOTDIR:-$HOME}/.zshrc" 2>/dev/null
fi

# Cache directory for eval outputs — regenerated only when the source binary changes
_zsh_cache="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
mkdir -p "$_zsh_cache"

_zsh_init_cached() {
  local name="$1" cache="$_zsh_cache/$1.zsh"
  shift
  [[ ! -f "$cache" || "$commands[$name]" -nt "$cache" ]] && "$@" > "$cache"
  source "$cache"
}
_zsh_init_cached mise mise activate zsh
_zsh_init_cached fzf fzf --zsh
_zsh_init_cached zoxide zoxide init zsh

_omp_config="${ZDOTDIR:-$HOME/.config/zsh}/omp.toml"
_omp_init="$_zsh_cache/omp.zsh"
if [[ ! -f "$_omp_init" || "$commands[oh-my-posh]" -nt "$_omp_init" || "$_omp_config" -nt "$_omp_init" ]]; then
  oh-my-posh init zsh --config "$_omp_config" > "$_omp_init"
fi
source "$_omp_init"
unset _zsh_cache _mise_init _fzf_init _zoxide_init _omp_config _omp_init

autoload -Uz add-zsh-hook
_omp_prompt_newline() { print "" }
(( ${precmd_functions[(I)_omp_prompt_newline]} )) || add-zsh-hook precmd _omp_prompt_newline

# Local overrides
[[ -f ${ZDOTDIR:-$HOME}/.zshrc.local ]] && source ${ZDOTDIR:-$HOME}/.zshrc.local

# Profiling output
[[ "$ZSHRC_PROFILE" == "1" ]] && zprof
