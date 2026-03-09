function update_nix --description "Update nix"
    nix-channel --update
    nix-env -iA nixpkgs.nix nixpkgs.cacert
end
