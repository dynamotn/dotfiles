# Rsync
alias syncdy 'rsync --delete -avhz'

# Netstat
alias open_ports 'netstat -tuplan'
alias listen_ports 'netstat -tuplen'

# Both are a complete netstat invocation, they take no argument
complete -c open_ports -f
complete -c listen_ports -f
