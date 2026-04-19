for brew in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew "$HOME/.linuxbrew/bin/brew"; do
  [[ -x $brew ]] && { eval "$("$brew" shellenv)"; break; }
done

source ~/.orbstack/shell/init.zsh 2>/dev/null || :
