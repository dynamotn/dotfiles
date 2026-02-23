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
    fisher install jorgebucaran/fisher </dev/null
    cat ~/.config/fish/plugins.list >>~/.config/fish/fish_plugins
end

# Install plugins
fish -c "fisher update </dev/null"
