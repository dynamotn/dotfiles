# @file dytoy_docs.sh
# @brief Read the doc blocks at the top of dytoy tool definitions
# @description A definition may start with `{{- /* doc` ... `*/ -}}` comment
# blocks holding YAML that describes the tool for `docs/dytoy.md`. These
# helpers read the blocks and give back the file without them, using plain
# text only (no chezmoi rendering). Blocks only count before the first line
# that is neither inside a block nor an opener; a later opener is ordinary
# text. Sourced (not executed); the caller sources dybatpho first.
# shellcheck shell=bash

#######################################
# @description Scan the leading blocks of a file
# @arg $1 string `blocks` prints block bodies, `strip` prints the rest
# @arg $2 string Definition file
# @stdout Block bodies separated by `---`, or the file without its blocks
# @exitcode 3 A block has no closing line
#######################################
function dytoy_docs::scan {
  dybatpho::expect_args mode file -- "$@"
  awk -v mode="$1" '
    state != 2 && /^\{\{- \/\* doc$/ { state = 1; if (mode == "blocks" && n++) print "---"; next }
    state == 1 && /^\*\/ -\}\}$/ { state = 0; next }
    state == 1 { if (mode == "blocks") print; next }
    { state = 2; if (mode == "strip") print }
    END { if (state == 1) exit 3 }
  ' "$2"
}

#######################################
# @description Print every doc block as a YAML document, with a `file` key added
# @arg $1 string Definition file
# @stdout YAML documents separated by `---`; nothing when there is no block
# @exitcode 1 A block has no closing line
#######################################
function dytoy_docs::blocks {
  dybatpho::expect_args file -- "$@"
  local file="$1" base body
  base="$(dybatpho::path_basename "${file}")"
  body="$(dytoy_docs::scan blocks "${file}")" \
    || dybatpho::die "${file}: doc block is not closed with '*/ -}}'"
  [[ -n "${body}" ]] || return 0
  BASE="${base}" yq '.file = strenv(BASE)' <<< "${body}"
}

#######################################
# @description Print the file with every leading doc block removed
# @arg $1 string Definition file
# @stdout File text without the blocks
# @exitcode 1 A block has no closing line
#######################################
function dytoy_docs::strip {
  dybatpho::expect_args file -- "$@"
  dytoy_docs::scan strip "$1" \
    || dybatpho::die "$1: doc block is not closed with '*/ -}}'"
}

#######################################
# @description Print the doc blocks of one definition, checked against it
# Each block's `name` must appear as a `name:` line of the definition, and a
# block without `url` gets the GitHub page of the definition's only repo.
# @arg $1 string Definition file
# @stdout YAML documents, one per block; nothing when there is no block
# @exitcode 1 A block is malformed or names no definition
#######################################
function dytoy_docs::definition_rows {
  dybatpho::expect_args file -- "$@"
  local file="$1" body text repos names name url=""
  body="$(dytoy_docs::blocks "${file}")" || return 1
  [[ -n "${body}" ]] || return 0
  text="$(dytoy_docs::strip "${file}")" || return 1
  repos="$(sed -nE 's/^[[:space:]]*repo:[[:space:]]*([^[:space:]#]+).*$/\1/p' <<< "${text}")"
  repos="$(sort -u <<< "${repos}")"
  [[ -z "${repos}" || "${repos}" == *$'\n'* ]] || url="https://github.com/${repos}"
  names="$(yq ea '[.name // ""] | .[]' <<< "${body}")"
  while read -r name; do
    awk -v name="${name}" '
      /^name:/ { value = $0; sub(/^name:[ \t]*/, "", value); sub(/[ \t]+$/, "", value); if (value == name) found = 1 }
      END { exit !found }
    ' <<< "${text}" \
      || dybatpho::die "$(dybatpho::path_basename "${file}"): doc name '${name}' matches no name: line"
  done <<< "${names}"
  URL="${url}" yq 'with(select(.url == null and strenv(URL) != ""); .url = strenv(URL))' <<< "${body}"
}

#######################################
# @description Print one line per problem in the collected doc rows
# @arg $1 string Categories file
# @stdin JSON array of doc rows, each with its `file`
# @stdout Problems, one per line; nothing when every row is valid
#######################################
function dytoy_docs::problems {
  dybatpho::expect_args categories -- "$@"
  local program
  program="$(
    cat << 'EOT'
load(strenv(CATS)) as $c
| (.[] | . as $e | ([$c[] | select(.category == $e.category)]) as $cat | (
    (select((.name // "") == "") | .file + ": missing name"),
    (select((.description // "") == "") | .file + ": " + .name + " has no description"),
    (select((.category // "") == "") | .file + ": " + .name + " has no category"),
    (select((.subcategory // "") == "") | .file + ": " + .name + " has no subcategory"),
    (select((.url // "") == "") | .file + ": " + .name + " has no url and not exactly one repo"),
    (select((.category // "") != "" and ($cat | length) == 0)
      | .file + ": " + .name + " has unknown category " + .category),
    (select(($cat | length) > 0 and ([$cat[0].subcategories[] | select(. == $e.subcategory)] | length) == 0)
      | .file + ": " + .name + " has unknown subcategory " + (.subcategory // ""))
  )),
  (group_by(.name) | .[] | select(length > 1)
    | "duplicate name " + .[0].name + " in " + ([.[].file] | join(", ")))
EOT
  )"
  CATS="$1" yq -r "${program}"
}

#######################################
# @description Collect every documented tool, validated and in doc order
# @arg $1 string Directory of the dytoy definitions
# @arg $2 string Extra entries: a YAML list of tools without a definition
# @arg $3 string Categories file: the ordered categories and subcategories
# @stdout JSON array of `{category, label, url, description}`
# @exitcode 1 A doc block is missing, malformed or invalid
#######################################
function dytoy_docs::collect {
  dybatpho::expect_args dir extra categories -- "$@"
  local dir="$1" extra="$2" file stream="" rows errors program
  for file in "${dir}"/*.yaml "${dir}"/*.yaml.tmpl "${extra}"; do
    [[ -f "${file}" ]] || continue
    if [[ "${file}" == "${extra}" ]]; then
      rows="$(BASE="$(dybatpho::path_basename "${extra}")" yq '.[] | .file = strenv(BASE) | split_doc' "${extra}")"
    else
      rows="$(dytoy_docs::definition_rows "${file}")" || return 1
    fi
    [[ -n "${rows}" ]] || continue
    [[ -z "${stream}" ]] || stream+=$'\n---\n'
    stream+="${rows}"
  done
  rows="$(yq ea -o json -I0 '[.]' <<< "${stream}")"
  errors="$(dytoy_docs::problems "$3" <<< "${rows}")"
  [[ -z "${errors}" ]] || dybatpho::die "${errors}"
  program="$(
    cat << 'EOT'
load(strenv(CATS)) as $c
| map(. as $e
  | ($c | to_entries | map(select(.value.category == $e.category)) | .[0]) as $cat
  | {
      "category": $e.category,
      "label": ($e.label // $e.name),
      "url": $e.url,
      "description": $e.description,
      "ci": $cat.key,
      "si": ($cat.value.subcategories | to_entries | map(select(.value == $e.subcategory)) | .[0].key),
      "oi": ($e.order // 1000000000),
      "li": (($e.label // $e.name) | downcase)
    })
| sort_by(.ci, .si, .oi, .li)
| map({"category": .category, "label": .label, "url": .url, "description": .description})
EOT
  )"
  CATS="$3" yq -o json -I0 "${program}" <<< "${rows}"
}

#######################################
# @description Render the generated part of `docs/dytoy.md`
# @arg $1 string Categories file: the ordered categories
# @stdin JSON array from `dytoy_docs::collect`
# @stdout The markdown between and including the generated-region markers
#######################################
function dytoy_docs::render {
  dybatpho::expect_args categories -- "$@"
  local rows categories category table program
  program="$(
    cat << 'EOT'
map(select(.category == strenv(CAT)))
| map(.cell = "[" + .label + "](" + .url + ")")
| map(with(select(.url == "none"); .cell = "`" + .label + "`"))
| map(with(select(.url == "text"); .cell = .label))
| .[] | "|" + .cell + "|" + (.description | sub("\|"; "\\|")) + "|"
EOT
  )"
  rows="$(cat)"
  categories="$(yq -r '.[].category' "$1")"
  printf '%s\n' '<!-- dytoy:begin (generated by scripts/dytoy_docs.sh, do not edit) -->'
  while read -r category; do
    table="$(CAT="${category}" yq -r "${program}" <<< "${rows}")" || return 1
    [[ -n "${table}" ]] || continue
    printf '## %s\n\n|Tool|Purpose|\n|----|-------|\n%s\n\n' "${category}" "${table}"
  done <<< "${categories}"
  printf '%s\n' '<!-- dytoy:end -->'
}

#######################################
# @description Put a generated region and its table of contents into the doc
# The region between the `dytoy:begin` and `dytoy:end` markers is replaced by
# the generated file, and the list between `<!-- toc -->` and
# `<!-- tocstop -->` becomes Usage plus one entry per generated category.
# @arg $1 string The doc, rewritten in place
# @arg $2 string The generated region, markers included
# @exitcode 0 The doc was already up to date
# @exitcode 1 The doc changed
#######################################
function dytoy_docs::update {
  dybatpho::expect_args doc generated -- "$@"
  local doc="$1" generated="$2" marker current updated
  for marker in '<!-- toc -->' '<!-- tocstop -->' '<!-- dytoy:begin' '<!-- dytoy:end -->'; do
    grep -qF -- "${marker}" "${doc}" || dybatpho::die "${doc}: marker ${marker} is missing"
  done
  # A closing marker above its opening one would drop the rest of the doc.
  awk '
    /^<!-- toc -->$/ { toc = NR } /^<!-- tocstop -->$/ { tocstop = NR }
    /^<!-- dytoy:begin/ { begin = NR } /^<!-- dytoy:end -->$/ { end = NR }
    END { exit !(toc < tocstop && begin < end) }
  ' "${doc}" || dybatpho::die "${doc}: marker <!-- tocstop --> or <!-- dytoy:end --> comes before its opening marker"
  current="$(< "${doc}")"
  updated="$(
    awk -v generated="${generated}" '
      function slug(text) {
        text = tolower(text)
        gsub(/[^a-z0-9 -]/, "", text)
        gsub(/ /, "-", text)
        return text
      }
      BEGIN {
        while ((getline line < generated) > 0) {
          region = region line "\n"
          if (line ~ /^## /) toc = toc "- [" substr(line, 4) "](#" slug(substr(line, 4)) ")\n"
        }
      }
      /^<!-- toc -->$/ { print; printf "\n- [Usage](#usage)\n%s\n", toc; skip = 1; next }
      /^<!-- tocstop -->$/ { skip = 0 }
      /^<!-- dytoy:begin/ { printf "%s", region; skip = 1; next }
      /^<!-- dytoy:end -->$/ { skip = 0; next }
      !skip { print }
    ' "${doc}"
  )"
  [[ "${updated}" != "${current}" ]] || return 0
  printf '%s\n' "${updated}" > "${doc}"
  return 1
}
