#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/tests/helpers/env.sh"
source "${SCRIPT_DIR}/tests/helpers/assert.sh"
source "${SCRIPT_DIR}/tests/helpers/git-fixtures.sh"

setup_tmp

# Build fixture: work repo + two bare remotes.
work="${TEST_TMPDIR}/work"
bare_a="${TEST_TMPDIR}/origin.git"
bare_b="${TEST_TMPDIR}/upstream.git"

create_bare_remote "$bare_a"
create_bare_remote "$bare_b"
create_work_repo "$work"
add_and_fetch "$work" origin "$bare_a"
add_and_fetch "$work" upstream "$bare_b"

# Setup branches:
hash_base=$(make_commit "$work" 'base')

# missing_br: only in origin (missing from upstream)
create_branch "$work" missing_br "$hash_base"
push_branch "$work" origin missing_br

# new_br: only in upstream (new in upstream)
create_branch "$work" new_br "$hash_base"
push_branch "$work" upstream new_br

# behind_br: upstream behind origin (fast-forwardable)
create_branch "$work" behind_br "$hash_base"
push_branch "$work" upstream behind_br
hash_ahead_of_base=$(make_commit "$work" 'ahead')
create_branch "$work" behind_br "$hash_ahead_of_base"
push_branch "$work" origin behind_br
git -C "$work" checkout main >/dev/null 2>&1

# ahead_br: upstream ahead of origin
create_branch "$work" ahead_br "$hash_base"
push_branch "$work" origin ahead_br
hash_ahead2=$(make_commit "$work" 'ahead2')
create_branch "$work" ahead_br "$hash_ahead2"
push_branch "$work" upstream ahead_br
git -C "$work" checkout main >/dev/null 2>&1

# diverged_br: diverged branch
git -C "$work" checkout -b div_a "$hash_base" >/dev/null 2>&1
hash_div_a=$(make_commit "$work" 'div-a')
create_branch "$work" diverged_br "$hash_div_a"
push_branch "$work" origin diverged_br
git -C "$work" checkout -b div_b "$hash_base" >/dev/null 2>&1
hash_div_b=$(make_commit "$work" 'div-b')
create_branch "$work" diverged_br "$hash_div_b"
push_branch "$work" upstream diverged_br
git -C "$work" checkout main >/dev/null 2>&1

git -C "$work" fetch origin --prune >/dev/null 2>&1
git -C "$work" fetch upstream --prune >/dev/null 2>&1

cd "$work"

run_tests() {

begin_test 'align: missing branch marked as push in dry-run'
local out
out="$(bash "$SCRIPT_UNDER_TEST" align -n origin upstream </dev/null 2>&1)" || true
assert_contains "$out" 'missing' \
	&& assert_contains "$out" 'push' \
	&& assert_contains "$out" 'missing_br' \
	&& end_test_ok

begin_test 'align: new branch marked as delete in dry-run'
local out2
out2="$(bash "$SCRIPT_UNDER_TEST" align -n --subset +new origin upstream </dev/null 2>&1)"
assert_contains "$out2" 'new' \
	&& assert_contains "$out2" 'delete' \
	&& assert_contains "$out2" 'new_br' \
	&& end_test_ok

begin_test 'align: behind branch marked as forward'
local out3
out3="$(bash "$SCRIPT_UNDER_TEST" align -n --subset behind origin upstream </dev/null 2>&1)"
assert_contains "$out3" 'behind' \
	&& assert_contains "$out3" 'forward' \
	&& assert_contains "$out3" 'behind_br' \
	&& end_test_ok

begin_test 'align --force: ahead branch marked as force'
local out4
out4="$(bash "$SCRIPT_UNDER_TEST" align --force -n --subset ahead origin upstream </dev/null 2>&1)"
assert_contains "$out4" 'ahead' \
	&& assert_contains "$out4" 'force' \
	&& assert_contains "$out4" 'ahead_br' \
	&& end_test_ok

begin_test 'align: diverged branch marked as push by default'
local out4b
out4b="$(bash "$SCRIPT_UNDER_TEST" align -n --subset diverged origin upstream </dev/null 2>&1)"
assert_contains "$out4b" 'diverged' \
	&& assert_contains "$out4b" 'push' \
	&& assert_contains "$out4b" 'diverged_br' \
	&& end_test_ok

begin_test 'align: candidates processed in sorted order (regression)'
local out5
out5="$(bash "$SCRIPT_UNDER_TEST" align -n origin upstream </dev/null 2>&1)"
# Extract ref names from porcelain-like output lines
local refs
refs="$(echo "$out5" | grep $'^[a-z]' | awk -F '\t' '{print $3}')"
local sorted_refs
sorted_refs="$(echo "$refs" | LC_ALL=C sort)"
assert_eq "$sorted_refs" "$refs" 'candidates should be sorted' && end_test_ok

begin_test 'align: dry-run summary has counts'
local out6
out6="$(bash "$SCRIPT_UNDER_TEST" align -n --subset +new origin upstream </dev/null 2>&1)"
assert_contains "$out6" 'Plan' \
	&& assert_contains "$out6" 'to push' \
	&& assert_contains "$out6" 'to delete' \
	&& end_test_ok

begin_test 'align: real push of missing branch'
local out7
out7="$(bash "$SCRIPT_UNDER_TEST" align --on-failure continue --subset missing origin upstream </dev/null 2>&1)"
assert_contains "$out7" 'done: missing_br' && end_test_ok

begin_test 'align: real delete of new branch'
# Re-fetch to see the new_br
git -C "$work" fetch upstream --prune >/dev/null 2>&1
local out8
out8="$(bash "$SCRIPT_UNDER_TEST" align --on-failure continue --yes --subset new origin upstream </dev/null 2>&1)"
assert_contains "$out8" 'done: new_br' && end_test_ok

begin_test 'align: nothing to align prints message'
local out9
out9="$(bash "$SCRIPT_UNDER_TEST" align --subset missing --exclude '*' origin upstream </dev/null 2>&1)"
assert_contains "$out9" 'No branches to align.' && end_test_ok

begin_test 'align: new excluded by default'
# Re-setup new_br for this test
push_branch "$work" upstream new_br
git -C "$work" fetch upstream --prune >/dev/null 2>&1
local out_no_new
out_no_new="$(bash "$SCRIPT_UNDER_TEST" align -n origin upstream </dev/null 2>&1)"
assert_not_contains "$out_no_new" 'new_br' && end_test_ok

begin_test 'align --subset +new: includes new'
local out_all
out_all="$(bash "$SCRIPT_UNDER_TEST" align -n --subset +new origin upstream </dev/null 2>&1)"
assert_contains "$out_all" 'new_br' && end_test_ok

begin_test 'align: delete confirmation skips on non-interactive without --yes'
local out_noyes
out_noyes="$(bash "$SCRIPT_UNDER_TEST" align --on-failure continue --subset +new origin upstream </dev/null 2>&1)" || true
assert_contains "$out_noyes" 'Refusing to delete' \
	&& assert_contains "$out_noyes" 'skipped' \
	&& end_test_ok

begin_test 'align --yes: skips delete confirmation'
# Re-setup new_br
push_branch "$work" upstream new_br
git -C "$work" fetch upstream --prune >/dev/null 2>&1
local out_yes
out_yes="$(bash "$SCRIPT_UNDER_TEST" align --on-failure continue --subset +new --yes origin upstream </dev/null 2>&1)" || true
assert_contains "$out_yes" 'done: new_br' && end_test_ok

begin_test 'align: dry-run skips delete confirmation'
# Re-setup new_br
push_branch "$work" upstream new_br
git -C "$work" fetch upstream --prune >/dev/null 2>&1
local out_dry_del
out_dry_del="$(bash "$SCRIPT_UNDER_TEST" align -n --subset +new origin upstream </dev/null 2>&1)"
assert_not_contains "$out_dry_del" 'Refusing to delete' \
	&& assert_contains "$out_dry_del" 'new_br' \
	&& end_test_ok

begin_test 'align: --subset +new adds new to defaults'
# Re-setup new_br
push_branch "$work" upstream new_br
git -C "$work" fetch upstream --prune >/dev/null 2>&1
local out_plus_new
out_plus_new="$(bash "$SCRIPT_UNDER_TEST" align -n --yes --subset +new origin upstream </dev/null 2>&1)"
assert_contains "$out_plus_new" 'new_br' && end_test_ok

begin_test 'align: --subset -missing removes missing from processing'
local out_minus_missing
out_minus_missing="$(bash "$SCRIPT_UNDER_TEST" align -n --subset -missing origin upstream </dev/null 2>&1)"
assert_not_contains "$out_minus_missing" 'missing_br' \
	&& assert_contains "$out_minus_missing" 'ahead_br' \
	&& end_test_ok

report_results
}
run_tests
