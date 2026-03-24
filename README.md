# git-sync

A pure Bash tool to compare and align branches and tags across Git remotes.

## Features

- **`git sync status`** — Compare branch or tag tips between your working copy and a remote, or between two remotes. Supports human-readable, porcelain, and name-only output modes.
- **`git sync align`** — Push branches or tags from a source to a target to bring them in sync. Supports dry-run, force/force-with-lease, and interactive failure recovery.
- **Include/exclude filtering** — Shell glob patterns (`-i`/`-x`) and pattern files (`-I`/`-X`) to narrow which refs are processed.
- **Subset filtering** — Restrict output or actions to specific categories: `new`, `missing`, `different`, `behind`, `ahead`, `diverged`, `same`.

## Requirements

- Git ≥ 2.0
- Bash ≥ 4.0

## Installation

Clone this repository (or download `git-sync.sh`) and set up a Git alias so you can invoke it as `git sync`:

```bash
git config --global alias.sync '!bash /path/to/git-sync.sh'
```

Replace `/path/to/git-sync.sh` with the absolute path to the script. For example:

```bash
git clone https://github.com/JulienCochuyt/git-sync-sh.git ~/git-sync-sh
git config --global alias.sync '!bash ~/git-sync-sh/git-sync.sh'
```

Verify the installation:

```bash
git sync help
```

## Usage

### status

```
git sync status [<options>]
git sync status [<options>] [@]<remote>
git sync status [<options>] [@]<remote> [@]<remote>
```

Compare branch or tag tips between your working copy and a remote, or between two remotes.

By default, `status` reads local tracking refs (`refs/remotes/<remote>/*`).
Prefix a remote with `@` to query it live via `git ls-remote` instead.
For tags (`-t`), remotes are always queried via `ls-remote`.

Examples:

```bash
git sync status origin
git sync status origin upstream
git sync status @origin @upstream
git sync status -t origin upstream
git sync status -p origin upstream
git sync status --subset missing,behind origin upstream
git sync status -i 'release/*' -x 'release/tmp-*' origin upstream
```

### align

```
git sync align [<options>] <source> <target>
```

Push branches or tags from a source remote to a target remote.
For branches, local tracking refs are used for comparison; pushes and deletions always target the real remote.
For tags, remotes are queried via `ls-remote`.

By default, refs only in the target (category `new`) are excluded to prevent
accidental deletions. Use `--all` or `--subset new` to include them.
When deleting refs, you will be prompted for confirmation. Use `--yes` to skip.

Examples:

```bash
git sync align origin upstream
git sync align --dry-run origin upstream
git sync align --all --yes origin upstream
git sync align --subset missing,behind origin upstream
git sync align -t origin upstream
git sync align --force-with-lease origin upstream
```

### help

```bash
git sync help
git sync status --help
git sync align --help
```

### Categories

Each ref is classified into exactly one category:

| Category    | Meaning                                              |
|-------------|------------------------------------------------------|
| `missing`   | Present in source but not in target.                 |
| `new`       | Present in target but not in source.                 |
| `behind`    | Target is ahead of source (fast-forward possible).   |
| `ahead`     | Source is ahead of target (fast-forward possible).    |
| `diverged`  | Source and target have diverged (no fast-forward).    |
| `different` | Hashes differ but direction cannot be determined.     |
| `same`      | Identical on both sides.                             |

**Availability by ref type:**

- **Branches** — `behind`, `ahead`, `diverged` are available when both sides have local refs. When one side uses `@remote`, only one direction is detectable (`behind` if source is local, `ahead` if target is local); the rest appear as `different`. When both sides use `@remote`, all differing branches appear as `different`.
- **Tags** — Differing tags are always classified as `different` (no direction).
- `new`, `missing`, and `same` are always available.

**`--subset` filtering:**

Use `--subset` to restrict which categories are reported (`status`) or processed (`align`). Categories can be combined with commas. Prefix with `+` to add to, or `-` to remove from, the default set. Plain entries replace the defaults entirely.

- **`status`** defaults to all categories except `same`. Use `--all` or `--subset +same` to include it.
- **`align`** defaults to all categories except `new` and `same`. Use `--all` or `--subset +new` to include deletions. `same` is never valid for `align`.

## Tests

Run the test suite:

```bash
bash tests/run.sh
```

## License

[GPL-2.0-only](LICENSE) — Copyright © 2026 Julien Cochuyt
