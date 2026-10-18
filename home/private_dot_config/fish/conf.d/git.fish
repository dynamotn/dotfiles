# Abbreviations rather than aliases: the full command lands on the line before
# it runs, so history keeps what really ran and a destructive one (`grh`,
# `gbd`, `gcl`) is seen in full before Enter.
abbr -a g git
abbr -a ga 'git add'
abbr -a gap 'git add -p'
abbr -a gai 'git add -i'
abbr -a gb 'git branch'
abbr -a gbd 'git branch -D'
abbr -a gbl 'git blame'
abbr -a gc 'git commit -v'
abbr -a gca 'git commit -v --amend'
abbr -a gcan 'git commit -v --amend --no-edit --reset-author'
abbr -a gcm --set-cursor 'git commit -m "%"'
abbr -a gcl 'git clean -df'
abbr -a gco 'git checkout'
abbr -a gcp 'git cherry-pick'
abbr -a gcpa 'git cherry-pick --abort'
abbr -a gcpc 'git cherry-pick --continue'
abbr -a gd 'git diff'
abbr -a gdc 'git diff --cached'
abbr -a gf 'git fetch'
abbr -a gfu 'git fetch --unshallow'
abbr -a gfa 'git fetch --all -p'
abbr -a gg "git log --graph --pretty=format:'%C(bold)%h%Creset%C(magenta)%d%Creset %s %C(yellow)<%an> %C(cyan)(%cr)%Creset' --abbrev-commit --date=relative"
abbr -a ggs "git log --graph --pretty=format:'%C(bold)%h%Creset%C(magenta)%d%Creset %s %C(yellow)<%an> %C(cyan)(%cr)%Creset' --abbrev-commit --date=relative --stat"
abbr -a ggp 'git log -p'
abbr -a gl 'git pull'
abbr -a gm 'git merge --ff'
abbr -a gmc 'git merge --continue'
abbr -a gmt 'git mergetool'
abbr -a gmv 'git mv'
abbr -a gn 'git clone --recursive --depth 1'
abbr -a gnb 'git checkout -b'
abbr -a gp 'git push'
abbr -a gpo 'git push -u origin'
abbr -a gph 'git push gh'
abbr -a gpt 'git push --tags'
abbr -a grb 'git rebase'
abbr -a grba 'git rebase --abort'
abbr -a grbi 'git rebase -i'
abbr -a grbc 'git rebase --continue'
abbr -a grh 'git reset --hard'
abbr -a grH 'git reset HEAD'
abbr -a grm 'git remote'
abbr -a grma 'git remote add'
abbr -a grmd 'git remote remove'
abbr -a grmu 'git remote set-url'
abbr -a grs 'git reset --soft'
abbr -a grv 'git revert'
abbr -a gs 'git status'
abbr -a gsh 'git show'
abbr -a gsm 'git submodule'
abbr -a gsn 'git snapshot' # View my dotfile git config
abbr -a gst 'git stash'
abbr -a gstd 'git stash drop'
abbr -a gstp 'git stash pop'
abbr -a gsts 'git stash show --text'
abbr -a gsu 'git submodule update --init --recursive --remote'
abbr -a gt 'git tag'
abbr -a gwt 'git worktree'

alias fgcs __caran_fzf_git_commit_search
alias fgb __caran_fzf_git_branch_switch
alias fgwt __caran_fzf_git_worktree_change

# The two `cd` shortcuts are functions rather than aliases: an alias wraps `cd`,
# so fish would offer directory completion for commands that take no argument.
function gR --description 'Go to the root of the repository'
    cd (git rev-parse --show-toplevel)
end

function gRu --description 'Go to the main checkout, or the superproject root'
    cd (git up)
end

# Neither those nor the fzf pickers take an argument
complete -c gR -f
complete -c gRu -f
complete -c fgcs -f
complete -c fgb -f
complete -c fgwt -f

set -q FZF_GIT_COMMIT_SEARCH_COMMAND; or set -g FZF_GIT_COMMIT_SEARCH_COMMAND "git log --color --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
