function __caran_terminal_workspace_rename_window -d "Rename terminal workspace window to new name" -a name
    if test -n "$ZELLIJ"
        zellij action rename-tab $name
    else if test -n "$TMUX"
        set -g OLD_TMUX_WINDOW_NAME (tmux list-windows -F '#{window_name}#{window_active}' | sed -n 's|^\(.*\)1$|\1|p')
        tmux rename-window $name
    end
end
