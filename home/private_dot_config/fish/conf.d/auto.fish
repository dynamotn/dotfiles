status --is-interactive || exit

# Past this many entries the listing scrolls the prompt away; set it to 0 to
# list every directory whatever its size.
set -q auto_ls_max_entries; or set -g auto_ls_max_entries 200
# Lines of the README shown under the listing; 0 shows none
set -q auto_ls_readme_lines; or set -g auto_ls_readme_lines 3
# Set it to 0 to drop the one-line git status shown on entering a repository
set -q auto_ls_git_summary; or set -g auto_ls_git_summary 1

function __auto_ls --on-variable PWD --description 'Automatically ls when the $PWD changes.'
    set -l listed true
    if test "$auto_ls_max_entries" -gt 0
        # An unmatched glob is no error for `set`, so an empty directory is fine
        set -l entries * .*
        if test (count $entries) -gt $auto_ls_max_entries
            printf '%d entries, listing skipped\n' (count $entries)
            set listed false
        end
    end
    if $listed
        eza --icons -la@ --color=always 2>/dev/null; or ls -laZ
    end
    __auto_ls_readme
    __auto_ls_git_summary
end

function __auto_ls_readme --description 'Show the first lines of the README of $PWD'
    test "$auto_ls_readme_lines" -gt 0; or return
    for name in README.md README.markdown README.rst README.txt README
        test -f $name; or continue
        set_color brblack
        string trim <$name | string match -rv '^$' | head -n $auto_ls_readme_lines \
            | string shorten -m (math "max(20, $COLUMNS - 4)") | string replace -r '^' '  '
        set_color normal
        return
    end
end

function __auto_ls_git_summary --description 'Show branch, upstream distance and changes on entering a repository'
    test "$auto_ls_git_summary" != 0; or return
    set -l root (git rev-parse --show-toplevel 2>/dev/null)
    if test -z "$root"
        set -e __auto_ls_repo
        return
    end
    # Once per repository, not at every `cd` inside it
    test "$root" = "$__auto_ls_repo"; and return
    set -g __auto_ls_repo $root

    set -l lines (git status --porcelain=v2 --branch 2>/dev/null)
    set -l parts (string replace -rf '^# branch\.head ' '' -- $lines)
    # `# branch.ab +AHEAD -BEHIND`, only when there is an upstream
    set -l distance (string match -rg '^# branch\.ab \+(\d+) -(\d+)$' -- $lines)
    if test -n "$distance[1]"; and test "$distance[1]$distance[2]" != 00
        set -a parts "↑$distance[1] ↓$distance[2]"
    end
    set -l changed (count (string match -rv '^#' -- $lines))
    test $changed -gt 0; and set -a parts "$changed changed"

    set_color brblack
    echo '  '(string join ' · ' -- $parts)
    set_color normal
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

# ctrl-o then a letter inserts at the cursor what a picker picks. Bound again
# whenever the key bindings are reset, as fish_vi_key_bindings does.
function __auto_bind_pickers --on-variable fish_key_bindings --description 'Bind ctrl-o sequences to the fzf pickers'
    for mode in default insert
        bind --mode $mode ctrl-o,b '__caran_fzf_insert __caran_fzf_git_branch_pick'
        bind --mode $mode ctrl-o,h '__caran_fzf_insert __caran_fzf_git_commit_search'
        bind --mode $mode ctrl-o,p '__caran_fzf_insert __caran_fzf_kube_pod_pick'
        bind --mode $mode ctrl-o,d '__caran_fzf_insert __caran_fzf_docker_pick'
    end
end

__auto_bind_pickers
