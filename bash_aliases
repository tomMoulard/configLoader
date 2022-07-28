#!/bin/bash
# $HOME/.bash_aliases
# ┌──────────────────────────────────┐
# │┏┓ ┏━┓┏━┓╻ ╻   ┏━┓╻  ╻┏━┓┏━┓┏━╸┏━┓│
# │┣┻┓┣━┫┗━┓┣━┫   ┣━┫┃  ┃┣━┫┗━┓┣╸ ┗━┓│
# │┗━┛╹ ╹┗━┛╹ ╹╺━╸╹ ╹┗━╸╹╹ ╹┗━┛┗━╸┗━┛│
# └──────────────────────────────────┘
# Maintainer:
#  tom at moulard dot org
# Complete_version:
#  You can file the updated version on the git repository
#  github.com/tommoulard/configloader

for method in GET HEAD POST PUT DELETE TRACE OPTIONS; do
	alias ${method}="lwp-request -m \"${method}\""
done

alias aria2c='aria2c --conf-path=$HOME/workspace/configLoader/aria2.conf'
alias bettercap='docker run -it --privileged --net=host bettercap/bettercap'
alias c='docker-compose'
alias cd..='cd ..'
alias check='awk -f $HOME/workspace/verifCode/verifCode.awk'
alias cls='clear'
alias cm='cmake'
alias d='dk'
alias dd='dd status="progress" conv="fdatasync"'
alias df='df -hT --total --sync'
alias diff='diff --color -u'
alias dk='docker'
alias egrep='egrep --color=auto'
alias feh='feh --scale-down --image-bg black  --borderless --auto-zoom -sort filename'
alias fgrep='fgrep --color=auto'
alias ga='git add'
alias gaa='git add -A'
alias gb='git branch'
alias gc='gcommit'
alias gcm='gcommit -S -m'
alias gcommit='git commit -S'
alias gct='git checkout'
alias gd='git diff'
alias gdb='gdb -q --args'
alias gits='git status'
alias gp='git push'
alias gpl='git pull -all'
alias grep='grep --color=auto'
alias gs='gits'
alias gsl='git shortlog -s'
alias gti='git'
alias h='history'
alias ip='ip -c'
alias ipy='ipython'
alias k='kubectl'
alias l1='ls -1'
alias l='ls -a'
alias la='ls -AF'
alias ll='ls --all -ll'
alias ls='ls --color=auto'
alias ma='make'
alias maek='ma'
alias make='ma'
alias md='mkdir -p'
alias meak='ma'
alias meka='ma'
alias mkae='ma'
alias mkea='ma'
alias mmdc='npx -p @mermaid-js/mermaid-cli mmdc'
alias myip='curl http://ipecho.net/plain; echo'
alias py='python'
alias q='exit'
alias qrcode='curl qrcode.show -d'
alias rb='ruby'
alias rd='rmdir'
alias reload='source $HOME/.bashrc'
alias rsync='rsync --progress --partial --archive --compress --stats --executability --hard-links'
alias show='toilet -F border -f future --gay'
alias shttp='python -m http.server'
alias sl='ls'
alias sudo='sudo '
alias t='terraform'
alias tor='docker run -it --rm -v /tmp/.X11-unix:/tmp/.X11-unix -e DISPLAY=unix$DISPLAY -v /dev/snd:/dev/snd --privileged --name tor-browser jess/tor-browser'
alias tree='tree -C'
alias nvrc='$EDITOR $HOME/.config/nvim/init.lua'
alias varc='$EDITOR $HOME/workspace/configLoader/bash_aliases'
alias vbpf='$EDITOR $HOME/workspace/configLoader/profile'
alias vbrc='$EDITOR $HOME/workspace/configLoader/bashrc'
alias vdwm='cd $HOME/workspace/dwm-fork/ && $EDITOR config.h && make && sudo make install && killall dwm && popd && cd -'
alias vi3c='$EDITOR $HOME/workspace/configLoader/config/i3/config'
alias vim="nvim"
alias vvrc='$EDITOR $HOME/workspace/configLoader/vimrc'
alias wgetall='wget --execute="robots = off" --mirror --convert-links --no-parent --wait=5'
alias xs='cd'
alias xt='extract'
alias yaegi='rlwrap yaegi'

source "${HOME}/workspace/configLoader/complete_alias"
for a in $(alias | tail -n +2 | cut -c 7- | cut -d'=' -f 1); do
    # echo $a
    complete -F _complete_alias "$a"
done

alias -- -='cd -'
alias ....='cd ../../..'
alias ...='cd ../..'
alias ..='cd ..'
alias _='sudo'

# vim:ft=bash
