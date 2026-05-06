#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
#
# Integration tests for the `unrelated` category (plan-unrelated.md).
#
# Builds two truly unrelated branches (each from a separate `git init`,
# no shared root commit) and asserts that `git sync status` and
# `git sync align` correctly classify them as `unrelated` and let the
# user filter on that category via --subset.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/tests/helpers/env.sh"
source "${SCRIPT_DIR}/tests/helpers/assert.sh"
source "${SCRIPT_DIR}/tests/helpers/git-fixtures.sh"

setup_tmp

# --- Build fixture: two unrelated branches in two bare remotes. ---
#
# repoA and repoB are independent `git init`s with no shared root.
# Each pushes its tip to a separate bare remote under the SAME branch
# name ("unrelated"). A consumer repo fetches both remotes, giving us
# differing tips for the same branch name with no common ancestor.
#
# A second branch `diverged_branch` (with a real common ancestor) is
# also pushed to each bare so we can verify Phase 3 subset filters
# distinguish `unrelated` from `diverged`.
bare_a="${TEST_TMPDIR}/origin.git"
bare_b="${TEST_TMPDIR}/upstream.git"
repo_a="${TEST_TMPDIR}/repoA"
repo_b="${TEST_TMPDIR}/repoB"
shared_repo="${TEST_TMPDIR}/shared"
consumer="${TEST_TMPDIR}/consumer"

create_bare_remote "$bare_a"
create_bare_remote "$bare_b"

create_work_repo "$repo_a"
make_commit "$repo_a" 'A1' >/dev/null
make_commit "$repo_a" 'A2' >/dev/null
git -C "$repo_a" push "$bare_a" 'main:refs/heads/unrelated' >/dev/null 2>&1

create_work_repo "$repo_b"
make_commit "$repo_b" 'B1' >/dev/null
make_commit "$repo_b" 'B2' >/dev/null
make_commit "$repo_b" 'B3' >/dev/null
git -C "$repo_b" push "$bare_b" 'main:refs/heads/unrelated' >/dev/null 2>&1

# `diverged_branch`: shared seed, then forked into two bares.
create_work_repo "$shared_repo"
make_commit "$shared_repo" 'shared1' >/dev/null
make_commit "$shared_repo" 'shared2' >/dev/null
git -C "$shared_repo" branch diverged_branch >/dev/null 2>&1
git -C "$shared_repo" remote add origin_remote "$bare_a"
git -C "$shared_repo" remote add upstream_remote "$bare_b"
git -C "$shared_repo" checkout diverged_branch >/dev/null 2>&1
make_commit "$shared_repo" 'origin_side' >/dev/null
git -C "$shared_repo" push origin_remote 'diverged_branch:refs/heads/diverged_branch' >/dev/null 2>&1
git -C "$shared_repo" reset --hard HEAD~1 >/dev/null 2>&1
make_commit "$shared_repo" 'upstream_side' >/dev/null
git -C "$shared_repo" push upstream_remote 'diverged_branch:refs/heads/diverged_branch' >/dev/null 2>&1

create_work_repo "$consumer"
add_and_fetch "$consumer" origin "$bare_a"
add_and_fetch "$consumer" upstream "$bare_b"

cd "$consumer"

run_tests() {

# --- Phase 2: unrelated category implemented ---

begin_test 'status: unrelated histories classified as unrelated (porcelain)'
local out_p
out_p="$(bash "$SCRIPT_UNDER_TEST" status -p origin upstream)"
assert_contains "$out_p" $'unrelated\tunrelated\t' \
	'unrelated branch should be reported under the unrelated category' \
	&& assert_not_contains "$out_p" $'diverged\tunrelated\t' \
		'unrelated branch should NOT be classified as diverged' \
	&& end_test_ok

begin_test 'status: unrelated emits "-/-" for behind/ahead counts (porcelain)'
local out_p2
out_p2="$(bash "$SCRIPT_UNDER_TEST" status -p origin upstream)"
local unrelated_line
unrelated_line="$(printf '%s\n' "$out_p2" | grep $'^unrelated\tunrelated\t')"
assert_contains "$unrelated_line" $'\t-\t-' \
	'count columns for unrelated should be "-" / "-"' \
	&& end_test_ok

begin_test 'status: unrelated histories appear under Unrelated section (human)'
local out_h
out_h="$(bash "$SCRIPT_UNDER_TEST" status origin upstream)"
assert_contains "$out_h" 'Unrelated: no common ancestor between origin and upstream' \
	'unrelated branch should be listed under the Unrelated section' \
	&& assert_contains "$out_h" '  unrelated' \
		'unrelated branch name should appear under the section' \
	&& end_test_ok

begin_test 'status: Diverged section excludes unrelated refs (human)'
local out_h2
out_h2="$(bash "$SCRIPT_UNDER_TEST" status origin upstream)"
assert_contains "$out_h2" 'Diverged: between origin and upstream (1)' \
	'true diverged refs should still be reported' \
	&& assert_contains "$out_h2" '  diverged_branch' \
	&& end_test_ok

# --- Phase 3: subset coverage ---

begin_test 'status: --subset unrelated keeps only unrelated refs (porcelain)'
local out_p3
out_p3="$(bash "$SCRIPT_UNDER_TEST" status -p --subset unrelated origin upstream)"
assert_contains "$out_p3" $'unrelated\tunrelated\t' \
	&& assert_not_contains "$out_p3" $'diverged\t' \
	&& assert_not_contains "$out_p3" $'same\t' \
	&& end_test_ok

begin_test 'status: --subset unrelated keeps only unrelated section (human)'
local out_h3
out_h3="$(bash "$SCRIPT_UNDER_TEST" status --subset unrelated origin upstream)"
assert_contains "$out_h3" 'Unrelated:' \
	&& assert_not_contains "$out_h3" 'Diverged:' \
	&& assert_not_contains "$out_h3" 'Same:' \
	&& end_test_ok

begin_test 'status: --subset -unrelated removes only the unrelated section'
local out_h4
out_h4="$(bash "$SCRIPT_UNDER_TEST" status --subset -unrelated origin upstream)"
assert_not_contains "$out_h4" 'Unrelated:' \
	&& assert_contains "$out_h4" 'Diverged:' \
	&& end_test_ok

begin_test 'status: --subset unrelated,diverged keeps both sections'
local out_p5
out_p5="$(bash "$SCRIPT_UNDER_TEST" status -p --subset unrelated,diverged origin upstream)"
assert_contains "$out_p5" $'unrelated\t' \
	&& assert_contains "$out_p5" $'diverged\t' \
	&& end_test_ok

begin_test 'status: invalid category in --subset still exits 1'
local out_bad rc=0
out_bad="$(bash "$SCRIPT_UNDER_TEST" status -p --subset bogus origin upstream 2>&1)" || rc=$?
assert_status 1 "$rc" 'invalid category should still exit 1' \
	&& assert_contains "$out_bad" 'Invalid category: bogus' \
	&& end_test_ok

# --- Phase 3: align defaults include unrelated ---

begin_test 'align: --subset unrelated valid for branches'
local out_align rc2=0
out_align="$(bash "$SCRIPT_UNDER_TEST" align -n --subset unrelated origin upstream 2>&1)" || rc2=$?
assert_status 0 "$rc2" 'align --subset unrelated should accept the category' \
	&& assert_contains "$out_align" $'unrelated\t' \
		'align should report the unrelated ref as a candidate' \
	&& end_test_ok

begin_test 'align: --subset -unrelated removes the unrelated ref from candidates'
local out_align2
out_align2="$(bash "$SCRIPT_UNDER_TEST" align -n --subset -unrelated origin upstream 2>&1 || true)"
assert_not_contains "$out_align2" $'unrelated\t' \
	'unrelated ref must be skipped when subtracted from defaults' \
	&& end_test_ok

# --- Phase 3: --tags rejects directional categories ---

begin_test 'status: --tags --subset unrelated is rejected'
local out_tags rc3=0
out_tags="$(bash "$SCRIPT_UNDER_TEST" status -t --subset unrelated origin upstream 2>&1)" || rc3=$?
assert_status 1 "$rc3" \
	&& assert_contains "$out_tags" 'unrelated' \
	&& end_test_ok

report_results
}
run_tests
