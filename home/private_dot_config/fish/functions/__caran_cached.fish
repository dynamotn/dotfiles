# Print the path of a file holding the output of a command, run again only
# when a watched path is newer than that file: startup reads a tool's init
# code instead of running the tool. Fails, printing nothing, when the command
# does. Usage: __caran_cached NAME [WATCHED_PATH...] -- COMMAND [ARG...]
function __caran_cached --description 'Cached output of a command'
    set -l separator (contains -i -- -- $argv); or return 2
    set -l name $argv[1]
    # A range that runs backwards counts down in fish, so none must stay none
    set -l watched
    test $separator -gt 2; and set watched $argv[2..(math $separator - 1)]
    set -l cmd $argv[(math $separator + 1)..-1]
    set -q cmd[1]; or return 2

    set -l cache_dir $HOME/.cache
    set -q XDG_CACHE_HOME[1]; and set cache_dir $XDG_CACHE_HOME
    set -l cache $cache_dir/fish/caran/$name

    set -l fresh 1
    if test -f $cache
        set -l built (path mtime -- $cache)
        for changed in (path mtime -- $watched)
            if test $changed -gt $built
                set fresh 0
                break
            end
        end
    else
        set fresh 0
    end

    if test $fresh -eq 0
        mkdir -p (path dirname -- $cache); or return 1
        # Written aside first, so a failed or cut-off run never leaves half a file
        if not $cmd >$cache.tmp
            command rm -f -- $cache.tmp
            return 1
        end
        command mv -f -- $cache.tmp $cache; or return 1
    end
    echo $cache
end
