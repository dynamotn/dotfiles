if type -q termux-setup-storage
    alias mise="PATH=$HOME/.local/bin:$PATH proot -b '$PREFIX/etc/resolv.conf:/etc/resolv.conf' -b '$PREFIX/etc/tls:/etc/ssl' mise"
end
