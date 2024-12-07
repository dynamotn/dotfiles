#!/usr/bin/env fish
set SETUP_DIR (dirname (readlink -m (status --current-filename)))

# Install fisher
if not functions -q fisher
  curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
  and fisher install jorgebucaran/fisher
end

fisher update < /dev/null

# Install nix
fish -c "install_nix"
