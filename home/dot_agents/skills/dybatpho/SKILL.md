---
name: dybatpho
description: Use when writing or changing any bash script longer than a few lines on this machine - sourcing the dybatpho library, declaring a CLI spec with dybatpho::opts, picking modules, error handling, logging, and running dyshellint before reporting done.
---

# Writing bash on dybatpho

Every bash script beyond a one-off snippet builds on
[dybatpho](https://github.com/dynamotn/dybatpho). Read the library's
`AGENT.md` and the `docs/<module>.md` of any module before calling a function
you have not used yet.

## Locate the library

1. A repository that vendors it: usually `scripts/lib/dybatpho` as a
   submodule. Source that copy.
2. Otherwise the shared checkout: `~/Working/personal/tools/dybatpho`.

A fresh clone or worktree may not have the submodule populated. Fetch it
before sourcing, the way `scripts/setup.sh` in the dotfiles does:

```bash
SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
if [[ ! -f "${SCRIPT_DIR}/lib/dybatpho/init.sh" ]]; then
  git -C "${SCRIPT_DIR}/.." submodule update --init "${SCRIPT_DIR}/lib/dybatpho"
fi
# shellcheck source=lib/dybatpho/init.sh
. "${SCRIPT_DIR}/lib/dybatpho/init.sh" --modules cli network
dybatpho::register_common_handlers
```

## Skeleton

```bash
#!/usr/bin/env bash
# @file name.sh
# @brief One line
# @description What the script does and why.
# ... source init.sh as above ...

#######################################
# @description Spec of name.sh
# @noargs
#######################################
function _spec_main {
  dybatpho::opts::setup "One line" MAIN_ARGS action:"_main"
  dybatpho::opts::param "Log level" LOG_LEVEL --log-level -l init:="info" \
    validate:"dybatpho::validate_log_level \$OPTARG"
  dybatpho::opts::flag "Dry run" DRY_RUN --dry-run -n on:true off:false init:="false"
  dybatpho::opts::disp "Show help" --help -h action:"dybatpho::generate_help _spec_main"
}

function _main {
  dybatpho::expect_args target -- "$@"
  dybatpho::info "Doing the thing"
  dybatpho::is file "${target}" || dybatpho::die "Not a file: ${target}"
}

dybatpho::generate_from_spec _spec_main
dybatpho::start_parse_opts "$@"
```

Rules the library expects:

- `set -euo pipefail` is installed by `init.sh`. Do not add your own trap or
  `set -e` on top; use `dybatpho::register_common_handlers` and
  `dybatpho::trap_add` from `process.sh`.
- Argument parsing goes through `dybatpho::opts::*`, never a hand-rolled
  `while getopts` or `case "$1"`.
- Validation uses `dybatpho::expect_args`, `dybatpho::is`, and the `validate`
  module, never ad-hoc regexes.
- Errors use `dybatpho::die` (exits) or `dybatpho::error` (returns 1).
  Logging uses `dybatpho::debug|info|warn|error`, never bare `echo` to stderr.
- Destructive work goes through `safety.sh` guards and honors `DRY_RUN`.
- Secrets go through `secret.sh`; never log or export their values.

## Modules

`init.sh` with no argument loads only the core modules (`string os logging
helpers process file secret array`). Name every other module explicitly with
`--modules <name>...`. Common picks:

| Need | Module |
|------|--------|
| options, help, subcommands | `cli` |
| curl, retries, JSON requests | `network` |
| tar/zip | `archive` |
| sudo once per run | `privilege` |
| package install | `pkg` |
| git operations | `git` |
| json/yaml query | `json` |
| rm/overwrite guards | `safety` |
| spinners, menus | `tui` |

A function that turns out undefined at run time almost always means its
module was not named in `--modules`.

## Library code in a repository

Sourced libraries follow `scripts/lib/<area>.sh`, functions `<area>::<verb>`,
private helpers `__<area>_<name>`, documented with `# @file`, `# @brief`,
`# @description`, `# @arg`, `# @stdout`, `# @exitcode`. Each library has a
matching `scripts/test/<area>.bats`; a new testable function gets a test in
the same commit.

## Before reporting done

```bash
dyshellint <changed scripts>     # shellcheck + shfmt + its own rules
./scripts/test.sh --related <changed files>   # or --all
```

Fix what `dyshellint` reports. Silence a rule only on purpose, with
`# dyshellint disable=<CODE> <reason>` on the line above.
