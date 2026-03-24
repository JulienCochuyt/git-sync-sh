#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/tests/helpers/env.sh"
source "${SCRIPT_DIR}/tests/helpers/assert.sh"
source "$SCRIPT_UNDER_TEST"

setup_tmp

# Helper: create a pattern file with the given line-ending style.
make_pattern_file() {
	local path="$1"
	local ending="$2"
	shift 2
	local content=''
	for line in "$@"; do
		content+="${line}${ending}"
	done
	printf '%s' "$content" > "$path"
}

run_tests() {

# --- LF line endings ---
begin_test 'load_pattern_file: LF endings'
local -a pats=()
make_pattern_file "${TEST_TMPDIR}/lf.txt" $'\n' 'alpha' 'beta' '' '# comment' 'gamma'
load_pattern_file "${TEST_TMPDIR}/lf.txt" pats
assert_eq 3 "${#pats[@]}" 'should have 3 patterns' \
	&& assert_eq 'alpha' "${pats[0]}" \
	&& assert_eq 'beta' "${pats[1]}" \
	&& assert_eq 'gamma' "${pats[2]}" \
	&& end_test_ok

# --- CRLF line endings ---
begin_test 'load_pattern_file: CRLF endings'
local -a pats2=()
make_pattern_file "${TEST_TMPDIR}/crlf.txt" $'\r\n' 'one' 'two'
load_pattern_file "${TEST_TMPDIR}/crlf.txt" pats2
assert_eq 2 "${#pats2[@]}" 'should have 2 patterns' \
	&& assert_eq 'one' "${pats2[0]}" \
	&& assert_eq 'two' "${pats2[1]}" \
	&& end_test_ok

# --- CR-only line endings ---
begin_test 'load_pattern_file: CR-only endings'
local -a pats3=()
make_pattern_file "${TEST_TMPDIR}/cr.txt" $'\r' 'first' 'second'
load_pattern_file "${TEST_TMPDIR}/cr.txt" pats3
assert_eq 2 "${#pats3[@]}" 'should have 2 patterns' \
	&& assert_eq 'first' "${pats3[0]}" \
	&& assert_eq 'second' "${pats3[1]}" \
	&& end_test_ok

# --- No trailing newline ---
begin_test 'load_pattern_file: no trailing newline'
local -a pats4=()
printf 'noterminator' > "${TEST_TMPDIR}/noterm.txt"
load_pattern_file "${TEST_TMPDIR}/noterm.txt" pats4
assert_eq 1 "${#pats4[@]}" \
	&& assert_eq 'noterminator' "${pats4[0]}" \
	&& end_test_ok

# --- Comments and blanks skipped ---
begin_test 'load_pattern_file: comments and blanks skipped'
local -a pats5=()
printf '# header\n\n  # indented comment\nkeep-me\n\n' > "${TEST_TMPDIR}/comments.txt"
load_pattern_file "${TEST_TMPDIR}/comments.txt" pats5
assert_eq 1 "${#pats5[@]}" \
	&& assert_eq 'keep-me' "${pats5[0]}" \
	&& end_test_ok

# --- Unreadable file ---
begin_test 'load_pattern_file: unreadable file exits with error'
local rc=0
(load_pattern_file '/nonexistent/file.txt' _x hint_status) &>/dev/null || rc=$?
assert_status 1 "$rc" && end_test_ok

report_results
}
run_tests
