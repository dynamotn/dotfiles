status is-interactive; or exit

# A command running at least this long sends a desktop notification when it
# ends; set it to 0 to turn notifications off.
set -q notify_long_command_seconds; or set -g notify_long_command_seconds 60
# Programs that hold the terminal until the user leaves them: their duration
# says nothing about work finishing. `notify_me` notifies on its own.
set -q notify_long_command_ignore; or set -g notify_long_command_ignore \
    vim nvim vi ssh ssht mosh less ov more man lazygit yazi zellij tmux btop top htop k9s fzf watch viddy notify_me
# Directories, as globs matched against $PWD, where nothing notifies
set -q notify_long_command_ignore_dirs; or set -g notify_long_command_ignore_dirs

function __notify_long_command --on-event fish_postexec --description 'Notify when a long command ends'
    set -l last_status $status
    test "$notify_long_command_seconds" -gt 0; or return
    test -n "$CMD_DURATION"; and test $CMD_DURATION -ge (math "$notify_long_command_seconds * 1000"); or return

    set -l program (string split -f1 ' ' -- (string trim -- $argv[1]))
    contains -- $program $notify_long_command_ignore; and return
    for dir in $notify_long_command_ignore_dirs
        string match -q -- $dir $PWD; and return
    end

    __caran_notify -- (__caran_notify_text $last_status $CMD_DURATION $argv[1])
end
