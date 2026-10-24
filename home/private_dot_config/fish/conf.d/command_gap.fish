status is-interactive; or exit

# The transient prompt collapses a run command to a single line and the next
# prompt starts right under its output, so in scrollback every command ran into
# the next one. A blank line after the output sets each command apart; the
# full-width top frame of the next prompt then reads as the divider.
# Set it to 0 to turn the gap off.
set -q command_gap_lines; or set -g command_gap_lines 1
# Commands that leave a fresh screen, where a gap would only push the prompt down
set -q command_gap_ignore; or set -g command_gap_ignore clear reset

function __command_gap --on-event fish_postexec --description 'Leave a gap between a command output and the next prompt'
    set -l command (string trim -- $argv[1])
    # A bare Enter ran nothing, and its prompt already sits on its own line
    test -n "$command"; or return
    contains -- (string split -f1 ' ' -- $command) $command_gap_ignore; and return

    # -N: without it string repeat adds a newline of its own, one line too many
    string repeat -Nn "$command_gap_lines" \n
end
