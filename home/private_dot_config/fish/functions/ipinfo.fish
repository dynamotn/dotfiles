function ipinfo --argument ip --description "Display IP info"
    curl -s "http://ipinfo.io/$ip"
end
