# ┌────────────────┐
# │╺━┓┏━┓╻ ╻╻╺┳┓┏━╸│
# │┏━┛┃ ┃┏╋┛┃ ┃┃┣╸ │
# │┗━╸┗━┛╹ ╹╹╺┻┛┗━╸│
# └────────────────┘
_z_cd() {
    cd "$@" || return "$?"

    if [ "$_ZO_ECHO" = "1" ]; then
        echo "$PWD"
    fi
}

z() {
    if [ "$#" -eq 0 ]; then
        _z_cd ~ || return "$?"
    elif [ "$#" -eq 1 ] && [ "$1" = '-' ]; then
        if [ -n "$OLDPWD" ]; then
            _z_cd "$OLDPWD" || return "$?"
        else
            echo 'zoxide: $OLDPWD is not set'
            return 1
        fi
    else
        result="$(zoxide query "$@")" || return "$?"
        if [ -d "$result" ]; then
            _z_cd "$result" || return "$?"
        elif [ -n "$result" ]; then
            echo "$result"
        fi
    fi
}


alias zi='z -i'

alias za='zoxide add'

alias zq='zoxide query'
alias zqi='zoxide query -i'

alias zr='zoxide remove'
alias zri='zoxide remove -i'


_zoxide_hook() {
    local exit_code=$? # Record exit status of previous command.
    if [ -z "${_ZO_PWD}" ]; then
        _ZO_PWD="${PWD}"
    elif [ "${_ZO_PWD}" != "${PWD}" ]; then
        _ZO_PWD="${PWD}"
        zoxide add
    fi
    return ${exit_code} # Restore the original exit code by returning it.
}

case "$PROMPT_COMMAND" in
    *_zoxide_hook*) ;;
    *) PROMPT_COMMAND="_zoxide_hook${PROMPT_COMMAND:+;${PROMPT_COMMAND}}" ;;
esac
