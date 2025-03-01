#!/usr/bin/env bash

update_main() {
	local changes
	changes=$(git status --porcelain 2>/dev/null | grep -c -E "^(M| M)")
	if [ "$changes" != "0" ]; then
		git stash
	fi

	local current_branch
	current_branch=$(git branch --show-current)
	local main_branch
	main_branch=$(git main)
	if [ "$branch" != "$main_branch" ]; then
		git checkout "$main_branch"
	fi
	git fetch -p
	git rebase "origin/$main_branch"
	if [ "$branch" != "$main_branch" ]; then
		git checkout "$branch"
	fi

	if [ "$changes" != "0" ]; then
		git stash pop
	fi
}

cmd="$1"
shift
"$cmd" "$@"
