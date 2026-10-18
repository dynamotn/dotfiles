function __caran_terminal_is_focused --description 'Whether the kitty window running this shell has the focus'
    # Unknown counts as unfocused: a notification too many beats a missed one
    set -q KITTY_WINDOW_ID; and set -q KITTY_LISTEN_ON; or return 1
    type -q kitten; and type -q jq; or return 1

    # Focused only when the OS window, its tab and the window itself all are
    kitten @ --to $KITTY_LISTEN_ON ls --match id:$KITTY_WINDOW_ID 2>/dev/null \
        | jq -e '.[0] | .is_focused and (.tabs[0] | .is_focused and .windows[0].is_focused)' >/dev/null 2>&1
end
