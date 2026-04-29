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
git sync status [<options>] @
git sync status [<options>] [@]<remote>
git sync status [<options>] <remote> @
git sync status [<options>] [@]<remote> [@]<remote>
```

Compare branch or tag tips between your working copy and a remote, or between two remotes.

By default, `status` reads local tracking refs (`refs/remotes/<remote>/*`).
Prefix a remote with `@` to query it live via `git ls-remote` instead.
For tags (`-t`), remotes are always queried via `ls-remote`.

Bare `@` (without a remote name) resolves the default remote and compares its
local tracking refs against its live state — a quick pre-fetch check. With two
remotes, bare `@` inherits the other remote's name. Not supported with `--tags`.

Examples:

```bash
git sync status @
git sync status origin
git sync status origin @
git sync status origin upstream
git sync status @origin @upstream
git sync status -t origin upstream
git sync status -ta origin upstream
git sync status -tA origin upstream
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
accidental deletions. Use `--subset new` or `--subset +new` to include them.
When deleting refs, you will be prompted for confirmation. Use `--yes` to skip.

Examples:

```bash
git sync align origin upstream
git sync align --dry-run origin upstream
git sync align --yes --subset +new origin upstream
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
- **Tags** — Differing tags are always classified as `different` (no direction). Use `--annotated` (`-a`) or `--lightweight` (`-A`) to filter by tag type.
- `new`, `missing`, and `same` are always available.

**`--subset` filtering:**

Use `--subset` to restrict which categories are reported (`status`) or processed (`align`). Categories can be combined with commas. Prefix with `+` to add to, or `-` to remove from, the default set. Plain entries replace the defaults entirely.

- **`status`** defaults to all categories except `same`. Use `--subset +same` to include it.
  `--porcelain` and `--name-only` always emit all categories; use `--subset -same` to exclude `same`.
- **`align`** defaults to all categories except `new` and `same`. Use `--subset +new` to include deletions. `same` is never valid for `align`.

## Configuration

Defaults can be set via `git config` under a `sync.*` namespace.
Both `status` and `align` share the same include/exclude and config keys.

```bash
git config sync.include 'release/*'
git config --add sync.include 'main'
git config sync.exclude 'dependabot/*'
git config sync.align.on-failure abort
git config sync.status.expand 5
git config sync.status.collapse 100
```

| Key | Scope | Description |
|-----|-------|-------------|
| `sync.include` | shared | Shell glob patterns selecting which refs to process (multi-value). |
| `sync.exclude` | shared | Shell glob patterns excluding refs (multi-value). |
| `sync.status.include` / `sync.align.include` | per-command | Override shared includes for one command. |
| `sync.status.exclude` / `sync.align.exclude` | per-command | Override shared excludes for one command. |
| `sync.status.expand` | status | Expand normally-collapsed categories when count ≤ N (default 5). |
| `sync.status.collapse` | status | Collapse normally-expanded categories when count ≥ N (default 50). |
| `sync.align.on-failure` | align | Failure strategy: `continue`, `fail-fast`, or `interactive` (default). |

### Include / Exclude Filtering

Ref filtering uses shell glob patterns and is available on both commands via CLI flags and config:

| Flag | Purpose |
|------|---------|
| `-i`, `--include <pattern>` | Include refs matching a shell glob. Repeatable. |
| `-I`, `--include-from <file>` | Read include patterns from a file (one per line, `#` comments). |
| `-x`, `--exclude <pattern>` | Exclude refs matching a shell glob. Repeatable. |
| `-X`, `--exclude-from <file>` | Read exclude patterns from a file (one per line, `#` comments). |

Patterns are resolved in three layers — shared config, per-command config, then CLI — with the following merge rules:

- **Includes** — CLI replaces earlier layers by default. Pass `-i +` to merge with config includes instead.
- **Excludes** — CLI merges with earlier layers by default. Pass `-x -` to replace config excludes, or `-x +` to re-assert all accumulated excludes after includes.

When no include patterns are specified anywhere, all refs are included.
When no exclude patterns are specified, nothing is excluded.

Excludes are applied after includes, but layer by layer: each layer's excludes
only apply to that layer's own includes. This means a later layer can introduce
refs that were excluded in an earlier layer. Pass `-x +` to re-assert all
accumulated excludes against the current layer's includes — useful when you
want to add refs via `-i +` while keeping earlier safety-net exclusions.

Example — sync only `release/*` branches, excluding temporaries:

```bash
# Via config (persistent)
git config sync.include 'release/*'
git config sync.exclude 'release/tmp-*'

# Via CLI (one-off)
git sync status -i 'release/*' -x 'release/tmp-*' origin upstream
```

Example — add a CLI include on top of config patterns:

```bash
git sync status -i + -i 'hotfix/*' origin upstream
```

## Tests

Run the test suite:

```bash
bash tests/run.sh
```

## License

[GPL-2.0-only](LICENSE) — Copyright © 2026 Julien Cochuyt
