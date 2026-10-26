# Secrets

Secrets are encrypted with [age](https://github.com/FiloSottile/age), one
identity per purpose: `personal`, `enterprise-<CODE>` for each company code in
[`home/.chezmoidata/companies.yaml`](../home/.chezmoidata/companies.yaml), and
`enterprise-shared` for what every company machine needs. Setup only decrypts
the identities it is told to (see [setup](./setup.md)), so a machine that is
not mine answers no and gets none of them.

## Layout

| Path                                 | Holds                                                |
|--------------------------------------|------------------------------------------------------|
| `~/.config/chezmoi/<identity>.key`   | Private age key of an identity, never committed      |
| `secrets/data/<identity>/`           | Private submodule: secret data of one identity       |
| `home/**/encrypted_*.age`            | Whole dotfiles that chezmoi decrypts on apply        |
| `schemas/secrets/`                   | Schema of every YAML file in `secrets/data/`         |

`home/.chezmoi.yaml.tmpl` lists the keys of the chosen identities as chezmoi's
age identities. Templates read the decrypted data at apply time, e.g.
`home/.chezmoitemplates/machine/secret.tmpl` takes the proxy and hostname from
`secrets/data/<identity>/machine.yaml.age`, so no value lands in this public
tree. Containers and CI decrypt nothing, and every such field stays empty.

## `chezmoi-dycrypt`

Encrypts and decrypts with a single identity. It handles two layouts:

- *data*: plaintext and `<file>.age` side by side under
  `secrets/data/<identity>/` (the default, `-f data`);
- *target*: the plaintext is a live file under `$HOME` or `/`, and the
  ciphertext goes to its chezmoi source path, with the attributes given by
  `-a` (e.g. `private,executable`).

```sh
chezmoi-dycrypt -i personal decrypt machine.yaml
chezmoi-dycrypt -i enterprise-F1 encrypt -r jira.yaml k8s.yaml
chezmoi-dycrypt -i personal -f ~/.config/foo -a private encrypt token.json
```

| Option                  | Effect                                              |
|-------------------------|-----------------------------------------------------|
| `-i`, `--identity-type` | Identity, default `personal`                        |
| `-f`, `--folder`        | Folder of the plaintext, default `data`             |
| `-a`, `--attributes`    | chezmoi attributes of the encrypted source file     |
| `-F`, `--force`         | Run even when the output is up to date              |
| `-D`, `--dry-run`       | Print what would happen                             |
| `-r`, `--remove`        | `encrypt` only: delete the plaintext afterwards     |

## Checks

- `./scripts/test.sh --secrets` validates the YAML data against
  `schemas/secrets/`.
- `pre-commit run --all-files` runs betterleaks and `detect-private-key`, so a
  plaintext secret does not get committed.
