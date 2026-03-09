if type -q sw_vers
    alias copy pbcopy
    alias paste pbpaste
else if type -q termux-setup-storage
    alias copy termux-clipboard-set
    alias paste termux-clipboard-get
else if test "$XDG_SESSION_TYPE" = wayland
    alias copy wl-copy
    alias paste wl-paste
else
    alias copy 'xsel -i -b'
    alias paste 'xsel -o -b'
end
