status is-interactive; or exit

# A command running at least this long sends a desktop notification when it
# ends; set it to 0 to turn notifications off.
set -q notify_long_command_seconds; or set -g notify_long_command_seconds 60
# Programs that hold the terminal until the user leaves them: their duration
# says nothing about work finishing.
set -q notify_long_command_ignore; or set -g notify_long_command_ignore \
    vim nvim vi ssh ssht mosh less ov more man lazygit yazi zellij tmux btop top htop k9s fzf watch viddy

function __notify_long_command --on-event fish_postexec --description 'Notify when a long command ends'
    set -l last_status $status
    test "$notify_long_command_seconds" -gt 0; or return
    test -n "$CMD_DURATION"; and test $CMD_DURATION -ge (math "$notify_long_command_seconds * 1000"); or return
    # The notification would reach the remote machine, not the one in front of the user
    set -q SSH_TTY; and return

    set -l program (string split -f1 ' ' -- (string trim -- $argv[1]))
    contains -- $program $notify_long_command_ignore; and return

    set -l title (test $last_status -eq 0; and echo Done; or echo "Failed ($last_status)")
    set -l shown (string shorten -m 80 -- $argv[1])
    # A command the history refuses carries a credential: do not show it either
    functions -q fish_should_add_to_history; and not fish_should_add_to_history "$argv[1]"
    and set shown $program
    set -l body "$shown · "(math -s0 $CMD_DURATION / 1000)s

    if test "$TERM" = xterm-kitty; and not set -q ZELLIJ
        # kitty shows it only while its window is out of focus
        printf '\e]99;i=fishdone:d=0:o=unfocused;%s\e\\' $title
        printf '\e]99;i=fishdone:d=1:p=body;%s\e\\' $body
    else if type -q osascript
        osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' -e 'end run' $title $body &>/dev/null
    else if type -q notify-send
        notify-send -a fish -- $title $body &>/dev/null
    end
end
