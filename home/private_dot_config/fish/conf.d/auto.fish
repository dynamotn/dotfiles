status --is-interactive || exit
function __auto_ls --on-variable PWD --description 'Automatically ls when the $PWD changes.'
    eza --icons -la@ 2>/dev/null; or ls -laZ
end

function __auto_prek_install --on-variable PWD --description 'Install the prek pre-commit Git shim when entering a repository.'
    command -sq prek; or printf 'Skipping prek install: command not found\n' 1>&2; return

    set -l repo_root (git rev-parse --show-toplevel 2>/dev/null); or return
    test -f "$repo_root/.pre-commit-config.yaml"; or test -f "$repo_root/prek.toml"; or return

    prek install --hook-type pre-commit --overwrite --quiet 2>/dev/null
end

function __auto_expand --on-variable fish_key_bindings
    set -l modes
    if test "$fish_key_bindings" = fish_default_key_bindings
        set modes default insert
    else
        set modes insert default
    end

    bind --mode $modes[1] . __caran_expand_dot 2>/dev/null
    bind --mode $modes[1] ! __caran_expand_bang 2>/dev/null
    bind --mode $modes[1] '$' __caran_expand_lastarg 2>/dev/null
    bind --mode $modes[2] --erase . ! '$' 2>/dev/null
end

function __remove_expand --on-event caran_uninstall
    bind -e . 2>/dev/null
    bind -e ! 2>/dev/null
    bind -e '$' 2>/dev/null
end

__auto_expand 2>/dev/null; true
