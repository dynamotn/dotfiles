function __caran_notify --description 'Send a notification to the desktop, and to Telegram with --remote'
    argparse remote -- $argv; or return 2
    set -l title $argv[1]
    set -l body $argv[2]

    if set -q _flag_remote
        __caran_notify_telegram "$title: $body"
    end

    # The desktop would be the remote machine's, not the one in front of the user
    set -q SSH_TTY; and return 0

    if test "$TERM" = xterm-kitty; and not set -q ZELLIJ
        # kitty shows it only while its window is out of focus
        printf '\e]99;i=fishdone:d=0:o=unfocused;%s\e\\' $title
        printf '\e]99;i=fishdone:d=1:p=body;%s\e\\' $body
        return 0
    end
    # Behind a multiplexer kitty cannot tell, so ask it
    __caran_terminal_is_focused; and return 0

    if type -q osascript
        osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' -e 'end run' $title $body &>/dev/null
    else if type -q notify-send
        notify-send -a fish -- $title $body &>/dev/null
    end
end
