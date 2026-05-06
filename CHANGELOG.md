# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- New `unknown` category for refs whose ancestry cannot be decided
  because the local repository is shallow. Previously these refs were
  silently bucketed under `unrelated`, which (mis)claims that the two
  histories share no common ancestor at all; with `unknown` we now
  acknowledge that the would-be common ancestor may merely lie below
  the shallow boundary.
  - Detection: when `git merge-base` returns empty, the classifier
    consults `git rev-parse --is-shallow-repository`; if true, it
    further checks via `git rev-list --max-parents=0 --count <tip>`
    whether each tip's walk reaches a parentless commit. If at least
    one tip is cut off by the shallow boundary, the verdict is
    `unknown` rather than `unrelated`.
  - Available in `full` direction mode (both sides local).
  - Included in default `--subset` for both `status` and `align`,
    consistent with `unrelated` and `diverged`.
  - Recognised by `--subset` (including the `+` / `-` modifiers and
    bash completion).
  - Human output: new `Unknown: ancestry inconclusive between <a>
    and <b>` section, rendered in red, followed by a one-line hint
    suggesting `git fetch --unshallow` / `--deepen=<N>`.
  - Porcelain output: new `unknown\t<ref>\t<src>\t<tgt>\t-\t-` line,
    matching the `unrelated` shape — no porcelain schema change.
- New `unrelated` category for refs whose tips share no common
  ancestor (e.g. independently initialised repositories pushed to the
  same branch name on the same remote, or histories created with
  `git checkout --orphan`). Previously these refs were silently
  bucketed under `diverged` with misleading
  `(N behind, M ahead)` counts derived from the full disjoint chain
  sizes.
  - Available in `full` direction mode (both sides local).
  - Included in default `--subset` for both `status` and `align`,
    consistent with the existing `diverged` treatment.
  - Recognised by `--subset` (including the `+` / `-` modifiers and
    bash completion).
  - Human output: new `Unrelated: no common ancestor between <a> and
    <b>` section, rendered in red.
  - Porcelain output: new `unrelated\t<ref>\t<src>\t<tgt>\t-\t-`
    line; `-` / `-` is emitted for the behind/ahead count columns
    since they would be meaningless without a common ancestor.

### Changed

- `classify_direction_relation`'s `full` arm now uses a single
  `git merge-base <a> <b>` call (capturing the ancestor hash) instead
  of two `git merge-base --is-ancestor` calls, which is what enables
  the new `unrelated` discrimination. Behaviour for `behind`,
  `ahead`, and `diverged` is unchanged.

### Fixed

- `--subset <bad-category>`, `--include-from <unreadable>`, and
  `--exclude-from <unreadable>` now exit cleanly with status 1 instead
  of 127. The argument parsers were passing the bare names
  `hint_status` / `hint_align` as the usage-hint callback, but the
  actual functions are `usage_hint_status` / `usage_hint_align`, so
  the error path tried to invoke a non-existent command.

## [1.1.0] - 2026-04-30

### Added

- Bash completion script (`git-sync-completion.bash`) with support for
  subcommands, options, remotes, branch/tag names, subset categories
  (including `+`/`-` prefixes and comma-separated values), and
  `--on-failure` strategies.

### Changed

- Options and positional arguments can now be mixed in any order for both
  `status` and `align` commands.

### Removed

- Removed the unused `--` option terminator.

## [1.0.0] - 2026-04-29

### Added

- `git sync status` command to compare branch or tag tips between remotes or
  against the working copy.
- `git sync align` command to push branches or tags from source to target.
- Human-readable, porcelain (`-p`), and name-only (`--name-only`) output modes.
- Include/exclude pattern filtering (`-i`, `-x`, `-I`, `-X`) with shell globs.
- Pattern file support (`--include-from`, `--exclude-from`).
- Subset filtering (`-s`/`--subset`) to restrict to specific categories:
  `new`, `missing`, `different`, `behind`, `ahead`, `diverged`, `same`.
- Tags mode (`-t`/`--tags`) for comparing and aligning tags.
- Tag type filtering: `--annotated`/`-a` (annotated only) and
  `--lightweight`/`-A` (lightweight only), mutually exclusive.
- Bare `@` shorthand for pre-fetch comparison against the default remote.
- Git-config support with layered pattern resolution (`sync.include`,
  `sync.exclude`, `sync.align.on-failure`, `sync.status.expand`,
  `sync.status.collapse`).
- Collapse/expand thresholds for human-readable output.
- Dry-run (`-n`), verbose (`-v`), and auto-confirm (`-y`) modes for `align`.
- Force push options: `--force`/`-f` and `--force-with-lease`/`-F`.
- Interactive failure recovery (`--on-failure`).
- Combined short options (e.g., `-nvt`).
- `--version` flag.
- `-h`/`--help` for global and per-command usage.
