#!/usr/bin/env fish
set SETUP_DIR (dirname (readlink -m (status --current-filename)))
set UPDATE false

# Install fisher
for i in (echo $argv | sed "s|--*|\n|g" | grep -v '^$')
  echo $i | read -l option value
  switch $option
    case u update
      set UPDATE true
  end
end
if not functions -q fisher; or eval $UPDATE
  curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
  and fisher install jorgebucaran/fisher
end

fisher update

# Install nix
fish -c "install_nix"
