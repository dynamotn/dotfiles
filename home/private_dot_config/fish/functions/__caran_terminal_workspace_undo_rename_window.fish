function __caran_terminal_workspace_undo_rename_window -d "Recover terminal workspace window to old name"
    if test -n "$ZELLIJ"
        zellij action undo-rename-tab
    else if test -n "$TMUX"
        tmux rename-window $OLD_TMUX_WINDOW_NAME
    end
end
