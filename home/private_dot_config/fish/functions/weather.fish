function weather --description "Display weather" --argument location
    curl -s "http://wttr.in/$location"
end
