# Usage: __caran_fzf FZF_OPTION...   (the choices come on stdin)
function __caran_fzf -d 'Run fzf with the options of the fzf plugin, quoting each argument'
    eval (__fzfcmd) (string escape -- $argv)
end
