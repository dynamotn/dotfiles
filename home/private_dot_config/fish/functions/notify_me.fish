function notify_me --description 'Run a command, then notify the desktop and Telegram however long it took'
    if test (count $argv) -eq 0
        echo 'Usage: notify_me COMMAND [ARG...]' >&2
        return 2
    end

    set -l start (date +%s)
    $argv
    set -l exit_status $status
    set -l duration_ms (math "($(date +%s) - $start) * 1000")

    __caran_notify --remote -- (__caran_notify_text $exit_status $duration_ms "$argv")
    return $exit_status
end
