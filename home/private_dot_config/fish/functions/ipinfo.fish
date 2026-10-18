function ipinfo --argument ip --description "Display IP info"
    curl -s "https://ipinfo.io/$ip"
end
