status --is-interactive || exit

# Past this many entries the listing scrolls the prompt away; set it to 0 to
# list every directory whatever its size.
set -q auto_ls_max_entries; or set -g auto_ls_max_entries 200

function __auto_ls --on-variable PWD --description 'Automatically ls when the $PWD changes.'
    if test "$auto_ls_max_entries" -gt 0
        # An unmatched glob is no error for `set`, so an empty directory is fine
        set -l entries * .*
        if test (count $entries) -gt $auto_ls_max_entries
            printf '%d entries, listing skipped\n' (count $entries)
            return
        end
    end
    eza --icons -la@ --color=always 2>/dev/null; or ls -laZ
end

function __auto_prek_install --on-variable PWD --description 'Install the prek pre-commit Git shim when entering a repository.'
    command -sq prek; or return

    set -l repo_root (git rev-parse --show-toplevel 2>/dev/null); or return
    test -f "$repo_root/.pre-commit-config.yaml"; or test -f "$repo_root/prek.toml"; or return
    # Already installed: skip the process spawn on every `cd` inside the repository
    set -l hook (git rev-parse --git-path hooks/pre-commit 2>/dev/null)
    test -f "$hook"; and string match -q '*prek*' <"$hook"; and return

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

__auto_expand
