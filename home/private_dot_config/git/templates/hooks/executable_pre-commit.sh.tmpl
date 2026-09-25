#!{{ .bash }}
# @file pre-commit.sh
# @brief Reject a commit that still has conflict markers
# @description Reject a commit whose staged changes still contain merge conflict markers,
# and list the files they are in.

conflicts=$(git diff --cached --name-only -G"<<<<<|=====|>>>>>")
if [[ -n "$conflicts" ]]; then
  echo
  echo "Unresolved merge conflicts in these files:"

  for conflict in "${conflicts[@]}"; do
    echo "$conflict"
  done

  exit 1
fi
exit 0
