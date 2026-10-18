function weather --description "Display weather" --argument location
    curl -s "https://wttr.in/$location"
end
