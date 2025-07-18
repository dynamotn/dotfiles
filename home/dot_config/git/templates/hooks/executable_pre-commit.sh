#!{{ .bash }}

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
