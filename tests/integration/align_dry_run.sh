#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/tests/helpers/env.sh"
source "${SCRIPT_DIR}/tests/helpers/assert.sh"
source "${SCRIPT_DIR}/tests/helpers/git-fixtures.sh"

setup_tmp

# Build fixture for dry-run and verbose tests.
work="${TEST_TMPDIR}/work"
bare_a="${TEST_TMPDIR}/origin.git"
bare_b="${TEST_TMPDIR}/upstream.git"

create_bare_remote "$bare_a"
create_bare_remote "$bare_b"
create_work_repo "$work"
add_and_fetch "$work" origin "$bare_a"
add_and_fetch "$work" upstream "$bare_b"

hash_base=$(make_commit "$work" 'base')

# missing_br: only in origin
create_branch "$work" missing_br "$hash_base"
push_branch "$work" origin missing_br

# new_br: only in upstream
create_branch "$work" new_br "$hash_base"
push_branch "$work" upstream new_br

git -C "$work" fetch origin --prune >/dev/null 2>&1
git -C "$work" fetch upstream --prune >/dev/null 2>&1

cd "$work"

run_tests() {

# --- Dry-run ---
begin_test 'align -n: dry-run does not mutate refs'
local before_refs
before_refs="$(git for-each-ref refs/remotes/upstream --format='%(refname)' | LC_ALL=C sort)"
bash "$SCRIPT_UNDER_TEST" align -n origin upstream </dev/null >/dev/null 2>&1
local after_refs
after_refs="$(git for-each-ref refs/remotes/upstream --format='%(refname)' | LC_ALL=C sort)"
assert_eq "$before_refs" "$after_refs" 'refs unchanged after dry-run' && end_test_ok

begin_test 'align -n: summary says Plan not Summary'
local out
out="$(bash "$SCRIPT_UNDER_TEST" align -n origin upstream </dev/null 2>&1)"
assert_contains "$out" 'Plan' \
	&& assert_not_contains "$out" 'Summary' \
	&& end_test_ok

begin_test 'align -n: dry-run summary uses future tense'
local out2
out2="$(bash "$SCRIPT_UNDER_TEST" align -n origin upstream </dev/null 2>&1)"
assert_contains "$out2" 'to push' \
	&& assert_contains "$out2" 'to delete' \
	&& assert_not_contains "$out2" 'skipped' \
	&& assert_not_contains "$out2" 'failed' \
	&& end_test_ok

begin_test 'align -n: no done: lines in dry-run'
local out3
out3="$(bash "$SCRIPT_UNDER_TEST" align -n origin upstream </dev/null 2>&1)"
assert_not_contains "$out3" 'done:' && end_test_ok

# --- Verbose ---
begin_test 'align -v -n: verbose dry-run prints commands with dry-run: prefix'
local out4
out4="$(bash "$SCRIPT_UNDER_TEST" align -v -n origin upstream </dev/null 2>&1)"
assert_contains "$out4" 'dry-run:' \
	&& assert_contains "$out4" 'git' \
	&& end_test_ok

begin_test 'align -v: verbose real run prints commands with run: prefix'
local out5
out5="$(bash "$SCRIPT_UNDER_TEST" align -v --subset missing origin upstream </dev/null 2>&1)"
assert_contains "$out5" 'run:' \
	&& assert_contains "$out5" 'git' \
	&& end_test_ok

# --- Real run produces Summary ---
begin_test 'align: real run summary'
# Re-setup: remove missing_br from both sides, then add it only in origin.
git -C "$work" push upstream ":refs/heads/missing_br" --force >/dev/null 2>&1 || true
git -C "$work" push origin ":refs/heads/missing_br" --force >/dev/null 2>&1
create_branch "$work" missing_br "$hash_base"
push_branch "$work" origin missing_br
git -C "$work" fetch origin --prune >/dev/null 2>&1
git -C "$work" fetch upstream --prune >/dev/null 2>&1
local out6
out6="$(bash "$SCRIPT_UNDER_TEST" align --on-failure continue origin upstream </dev/null 2>&1)"
assert_contains "$out6" 'Summary' \
	&& assert_contains "$out6" 'pushed' \
	&& end_test_ok

# --- Combined short options ---

# Re-setup: real run above aligned everything, so recreate missing_br divergence
git -C "$work" push upstream ":refs/heads/missing_br" --force >/dev/null 2>&1
git -C "$work" fetch origin --prune >/dev/null 2>&1
git -C "$work" fetch upstream --prune >/dev/null 2>&1

begin_test 'align: -vn expands to -v -n'
local combo_vn
combo_vn="$(bash "$SCRIPT_UNDER_TEST" align -vn origin upstream </dev/null 2>&1)"
assert_contains "$combo_vn" 'dry-run:' \
	&& assert_contains "$combo_vn" 'Plan' \
	&& end_test_ok

begin_test 'align: -ns missing expands to -n -s missing'
local combo_ns
combo_ns="$(bash "$SCRIPT_UNDER_TEST" align -ns missing origin upstream </dev/null 2>&1)"
assert_contains "$combo_ns" 'Plan' && end_test_ok

report_results
}
run_tests
