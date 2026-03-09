function install_nix --description "Install or update nix"
    if type -q nix
        update_nix
    else
        type -q sw_vers
        and curl -sSL https://nixos.org/nix/install | bash -s -- --darwin-use-unencrypted-nix-store-volume
        or curl -sSL https://nixos.org/nix/install | bash -s -- --no-daemon
    end
end
