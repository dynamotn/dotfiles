function __caran_history_secret_patterns --description 'Print the regexes of a command line carrying a credential'
    set -l name '(?i:token|secret|password|passwd|passphrase|api_?key|access_?key|private_?key)'
    # An environment assignment: `GH_TOKEN=… cmd`, `export API_KEY=…`
    echo '\b[A-Z0-9_]*(TOKEN|SECRET|PASSWORD|PASSWD|PASSPHRASE|API_?KEY|ACCESS_?KEY|PRIVATE_?KEY)[A-Z0-9_]*=\S+'
    # A fish assignment: `set -gx GITLAB_TOKEN …`
    echo '\bset\s+(-\S+\s+)*[A-Za-z0-9_]*'$name'[A-Za-z0-9_]*\s+\S+'
    # A credential handed to a flag: `--password …`, `--token=…`, `--client-secret …`
    echo '--[a-z-]*'$name'(=|\s+)[^\s<|-]\S*'
    # An HTTP authorization header, or a user:password pair in a URL
    echo '(?i)authorization:\s*(bearer|basic|token)\s+\S+'
    echo '://[^/\s:@]+:[^/\s@]+@'
    # Well-known token shapes: GitHub, GitLab, Slack, AWS, OpenAI and Anthropic style keys
    echo '\b(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|glpat-[A-Za-z0-9_-]{20,}|xox[abposr]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9_-]{20,})'
    # Patterns of this machine, from per_machine.fish or secret.fish
    set -q history_secret_patterns; and printf '%s\n' $history_secret_patterns
end
