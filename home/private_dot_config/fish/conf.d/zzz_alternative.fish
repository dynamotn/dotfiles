# Only at the prompt: a `fish -c` or a fish script expects the classic tools,
# whose flags and output the replacements do not share.
status is-interactive; or exit

type -q grc; and __caran_setup_grc
type -q nvimpager; and alias cat nvimpager
type -q eza; and alias ls 'eza --icons auto --color=always'
type -q sping; and alias ping sping
type -q btop; and alias top btop
type -q procs; and alias ps procs
type -q viddy; and alias watch viddy
type -q dust; and alias du dust
type -q duf; and alias df duf
type -q curlie; and alias curl curlie
type -q q; and alias dig q
type -q ov; and alias less ov; and alias more ov
type -q btop; and alias htop btop
