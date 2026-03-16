# ——— Profiling (set ZSHRC_PROFILE=1 to enable) ———
[[ "$ZSHRC_PROFILE" == "1" ]] && zmodload zsh/zprof

# ——— Options ———
setopt auto_cd correct histignorealldups interactive_comments sharehistory

# ——— Zinit bootstrap ———
ZINIT_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"

if [[ ! -d $ZINIT_HOME/.git ]]; then
  mkdir -p ${ZINIT_HOME:h}
  git clone --depth=1 https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

source "$ZINIT_HOME/zinit.zsh"

# ——— Shell performance ———
setopt promptsubst
DISABLE_MAGIC_FUNCTIONS=true

# Faster completion init — XDG-compliant cache path
_zcompdump_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
mkdir -p "$_zcompdump_dir"
autoload -Uz compinit
compinit -C -d "$_zcompdump_dir/.zcompdump"
unset _zcompdump_dir

# Optional zcompile for faster source loading
if [[ ! -f "${ZDOTDIR:-$HOME}/.zshrc.zwc" ]] || \
   [[ "${ZDOTDIR:-$HOME}/.zshrc" -nt "${ZDOTDIR:-$HOME}/.zshrc.zwc" ]]; then
  zcompile "${ZDOTDIR:-$HOME}/.zshrc" 2>/dev/null
fi

# ——— Prompt ———
export PURE_PROMPT_SYMBOL="λ"
zinit ice pick"async.zsh" src"pure.zsh"
zinit light sindresorhus/pure

# ——— Plugins ———
zinit ice wait"0" lucid
zinit light marlonrichert/zsh-autocomplete

zinit ice wait"0" lucid
zinit light zsh-users/zsh-autosuggestions

zinit ice wait"0" lucid
zinit light zsh-users/zsh-completions

# Syntax highlighting must load last
zinit ice wait"1" lucid
zinit light zsh-users/zsh-syntax-highlighting

# ——— atuin ———
zinit ice as"command" from"gh-r" bpick"atuin-*.tar.gz" mv"atuin*/atuin -> atuin" \
    atclone"./atuin init zsh > init.zsh; ./atuin gen-completions --shell zsh > _atuin" \
    atpull"%atclone" src"init.zsh"
zinit light atuinsh/atuin

# ——— mise ———
zinit as="command" lucid from="gh-r" for \
    id-as="usage" \
    atpull="%atclone" \
    jdx/usage

zinit as="command" lucid from="gh-r" for \
    id-as="mise" mv="mise* -> mise" \
    atclone="chmod +x ./mise*;./mise* completion zsh > _mise" \
    atpull="%atclone" \
    atload='eval "$(mise activate zsh)"' \
    jdx/mise

# ——— fzf ———
zinit ice from"gh-r" as"program" atload'eval "$(fzf --zsh)"'
zinit light junegunn/fzf

# ——— zoxide ———
unalias zi # Frees up `zi` for zoxide from `zinit` alias
zinit ice wait"2" as"command" from"gh-r" lucid \
  mv"zoxide*/zoxide -> zoxide" \
  atload'eval "$(zoxide init zsh)"'
zinit light ajeetdsouza/zoxide

# ——— Aliases ———
alias mr='mise run'
alias mi='mise install'

# ——— Keybinds ———
bindkey -M emacs \
    "^[p"   .history-search-backward \
    "^[n"   .history-search-forward \
    "^P"    .up-line-or-history \
    "^[OA"  .up-line-or-history \
    "^[[A"  .up-line-or-history \
    "^N"    .down-line-or-history \
    "^[OB"  .down-line-or-history \
    "^[[B"  .down-line-or-history \

# ——— Local config ———
[[ -f ${ZDOTDIR:-$HOME}/.zshrc.local ]] && source ${ZDOTDIR:-$HOME}/.zshrc.local

# ——— Profiling output ———
[[ "$ZSHRC_PROFILE" == "1" ]] && zprof
