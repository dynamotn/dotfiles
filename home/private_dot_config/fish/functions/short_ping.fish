function short_ping --wraps ping --description "ping with only 5 packets"
    command ping -c 5 $argv
end
