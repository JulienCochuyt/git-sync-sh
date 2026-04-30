# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
