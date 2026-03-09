function fast_ping --wraps ping --description "ping with short interval"
    command ping -c 50 -i0.2 $argv
end
