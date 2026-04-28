#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
# Integration tests for bare @ shorthand in status command.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/tests/helpers/env.sh"
source "${SCRIPT_DIR}/tests/helpers/assert.sh"
source "${SCRIPT_DIR}/tests/helpers/git-fixtures.sh"

setup_tmp

# Build fixture: work repo + two bare remotes (origin, upstream).
# Push a branch to origin so we have tracking refs to compare against ls-remote.
work="${TEST_TMPDIR}/work"
bare_origin="${TEST_TMPDIR}/origin.git"
bare_upstream="${TEST_TMPDIR}/upstream.git"

create_bare_remote "$bare_origin"
create_bare_remote "$bare_upstream"
create_work_repo "$work"
add_and_fetch "$work" origin "$bare_origin"
add_and_fetch "$work" upstream "$bare_upstream"

# Push main to both remotes
push_branch "$work" origin main
push_branch "$work" upstream main

# shared: same commit on both
hash_shared=$(make_commit "$work" 'shared')
create_branch "$work" shared "$hash_shared"
push_branch "$work" origin shared
push_branch "$work" upstream shared

# origin_extra: exists only on origin (will be "missing" comparing origin to upstream)
create_branch "$work" origin_extra "$hash_shared"
push_branch "$work" origin origin_extra

# Fetch to update tracking refs
git -C "$work" fetch origin --prune >/dev/null 2>&1
git -C "$work" fetch upstream --prune >/dev/null 2>&1

# Set upstream so default remote resolves to origin
git -C "$work" checkout main >/dev/null 2>&1
git -C "$work" branch --set-upstream-to=origin/main main >/dev/null 2>&1

cd "$work"

run_tests() {

# --- 1-arg bare @ ---

begin_test 'status @: equivalent to status <default_remote> @<default_remote>'
local out_at out_explicit
out_at="$(bash "$SCRIPT_UNDER_TEST" status -p '@')"
out_explicit="$(bash "$SCRIPT_UNDER_TEST" status -p origin '@origin')"
assert_eq "$out_explicit" "$out_at" \
	'bare @ should produce same porcelain as explicit origin @origin' \
	&& end_test_ok

begin_test 'status @: porcelain shows same category (tracking refs match remote)'
local out_same
out_same="$(bash "$SCRIPT_UNDER_TEST" status -p '@')"
assert_contains "$out_same" 'same' \
	'with no divergence, all branches should be same' \
	&& end_test_ok

# --- 2-arg: remote @ ---

begin_test 'status origin @: equivalent to status origin @origin'
local out_short out_long
out_short="$(bash "$SCRIPT_UNDER_TEST" status -p origin '@')"
out_long="$(bash "$SCRIPT_UNDER_TEST" status -p origin '@origin')"
assert_eq "$out_long" "$out_short" \
	'origin @ should produce same porcelain as origin @origin' \
	&& end_test_ok

# --- 2-arg: @ remote ---

begin_test 'status @ origin: equivalent to status @origin origin'
local out_rev out_rev_explicit
out_rev="$(bash "$SCRIPT_UNDER_TEST" status -p '@' origin)"
out_rev_explicit="$(bash "$SCRIPT_UNDER_TEST" status -p '@origin' origin)"
assert_eq "$out_rev_explicit" "$out_rev" \
	'@ origin should produce same porcelain as @origin origin' \
	&& end_test_ok

# --- 2-arg: @ @remote (inherit remote name from @-prefixed arg) ---

begin_test 'status @ @origin: expands to @origin @origin'
local out_at_at out_at_at_explicit
out_at_at="$(bash "$SCRIPT_UNDER_TEST" status -p '@' '@origin')"
out_at_at_explicit="$(bash "$SCRIPT_UNDER_TEST" status -p '@origin' '@origin')"
assert_eq "$out_at_at_explicit" "$out_at_at" \
	'@ @origin should produce same porcelain as @origin @origin' \
	&& end_test_ok

# --- Error: @ @ ---

begin_test 'status @ @: error when both args are bare @'
local out_err rc=0
out_err="$(bash "$SCRIPT_UNDER_TEST" status '@' '@' 2>&1)" || rc=$?
assert_eq 1 "$rc" 'should exit with code 1' \
	&& assert_contains "$out_err" 'Cannot use bare @ for both arguments' \
	'error message should mention both bare @' \
	&& end_test_ok

# --- Tags mode with bare @ ---

begin_test 'status -t @: tags mode rejects bare @'
local out_tags_err rc_tags=0
out_tags_err="$(bash "$SCRIPT_UNDER_TEST" status -t '@' 2>&1)" || rc_tags=$?
assert_eq 1 "$rc_tags" 'should exit with code 1' \
	&& assert_contains "$out_tags_err" 'Bare @ is not supported with --tags' \
	'error message should explain bare @ + tags incompatibility' \
	&& end_test_ok

begin_test 'status -t origin @: tags mode rejects bare @ in two-arg form'
local out_tags_err2 rc_tags2=0
out_tags_err2="$(bash "$SCRIPT_UNDER_TEST" status -t origin '@' 2>&1)" || rc_tags2=$?
assert_eq 1 "$rc_tags2" 'should exit with code 1' \
	&& assert_contains "$out_tags_err2" 'Bare @ is not supported with --tags' \
	'error message should explain bare @ + tags incompatibility' \
	&& end_test_ok

}

run_tests
report_results
