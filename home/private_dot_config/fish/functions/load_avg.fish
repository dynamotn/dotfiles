function load_avg --description "Load average"
    uptime | awk -F'[a-z]: ' '{ print $2 }'
end
