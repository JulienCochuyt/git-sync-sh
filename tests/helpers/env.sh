#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
# Test environment setup — sourced by every test file.

set -euo pipefail

export LC_ALL=C

# Deterministic git identity for reproducible commit hashes.
export GIT_AUTHOR_NAME='Test Author'
export GIT_AUTHOR_EMAIL='test@example.com'
export GIT_COMMITTER_NAME='Test Author'
export GIT_COMMITTER_EMAIL='test@example.com'

# Locate the script under test (absolute path).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly SCRIPT_UNDER_TEST="${SCRIPT_DIR}/git-sync.sh"

# Per-test temp directory with automatic cleanup.
TEST_TMPDIR=''

setup_tmp() {
	TEST_TMPDIR="$(mktemp -d)"
	trap cleanup_tmp EXIT
}

cleanup_tmp() {
	if [[ -n "$TEST_TMPDIR" && -d "$TEST_TMPDIR" ]]; then
		rm -rf "$TEST_TMPDIR"
	fi
}

# Track test counts for the harness.
_TESTS_RUN=0
_TESTS_FAILED=0
_CURRENT_TEST_NAME=''

begin_test() {
	_CURRENT_TEST_NAME="$1"
	((_TESTS_RUN += 1))
}

end_test_ok() {
	printf '  PASS: %s\n' "$_CURRENT_TEST_NAME"
}

end_test_fail() {
	((_TESTS_FAILED += 1))
	printf '  FAIL: %s\n' "$_CURRENT_TEST_NAME"
}

report_results() {
	printf '\n%d tests, %d failed\n' "$_TESTS_RUN" "$_TESTS_FAILED"
	((_TESTS_FAILED == 0))
}
