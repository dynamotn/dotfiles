function __caran_fzf_chezmoi_edit -d 'Edit a chezmoi-managed file'
    type -q chezmoi; or return 1
    # Encrypted files stay out of the list, and there is no preview: showing
    # the target would render templates, which can read secrets.
    chezmoi managed --include=files --exclude=encrypted,externals --path-style=absolute 2>/dev/null \
        | __caran_fzf --prompt='chezmoi> ' | read -l target

    if test -n "$target"
        chezmoi edit $target
    end

    commandline -f repaint
end
