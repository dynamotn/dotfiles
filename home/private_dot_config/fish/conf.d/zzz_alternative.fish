# Only at the prompt: a `fish -c` or a fish script expects the classic tools,
# whose flags and output the replacements do not share.
status is-interactive; or exit

# Names an alternative took over, which grc must not wrap just to be overwritten
set -l replaced
type -q nvimpager; and alias cat nvimpager; and set -a replaced cat
type -q eza; and alias ls 'eza --icons auto --color=always'
type -q sping; and alias ping sping; and set -a replaced ping
type -q btop; and alias top btop
type -q procs; and alias ps procs; and set -a replaced ps
type -q viddy; and alias watch viddy
type -q dust; and alias du dust; and set -a replaced du
type -q duf; and alias df duf; and set -a replaced df
type -q curlie; and alias curl curlie
type -q doggo; and alias dig doggo; and set -a replaced dig
type -q ov; and alias less ov; and alias more ov
type -q btop; and alias htop btop

type -q grc; and __caran_setup_grc $replaced
