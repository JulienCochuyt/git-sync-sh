#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/tests/helpers/env.sh"
source "${SCRIPT_DIR}/tests/helpers/assert.sh"
source "${SCRIPT_DIR}/tests/helpers/git-fixtures.sh"

setup_tmp

# Build fixture with a locked remote to trigger push failures.
work="${TEST_TMPDIR}/work"
bare_a="${TEST_TMPDIR}/origin.git"
bare_b="${TEST_TMPDIR}/upstream.git"

create_bare_remote "$bare_a"
create_bare_remote "$bare_b"
create_work_repo "$work"
add_and_fetch "$work" origin "$bare_a"
add_and_fetch "$work" upstream "$bare_b"

hash_base=$(make_commit "$work" 'base')

# Two branches missing from upstream so we have multiple candidates
create_branch "$work" br_first "$hash_base"
push_branch "$work" origin br_first
create_branch "$work" br_second "$hash_base"
push_branch "$work" origin br_second

git -C "$work" fetch origin --prune >/dev/null 2>&1
git -C "$work" fetch upstream --prune >/dev/null 2>&1

# Lock upstream to reject all pushes
lock_bare_repo "$bare_b"

cd "$work"

run_tests() {

# --- fail-fast ---
begin_test 'align --on-failure fail-fast: stops on first failure'
local out rc=0
out="$(bash "$SCRIPT_UNDER_TEST" align --on-failure fail-fast --subset missing origin upstream </dev/null 2>&1)" || rc=$?
assert_status 1 "$rc" 'should fail'
# Only one "failed:" line should appear (stops after first)
local fail_count
fail_count="$(echo "$out" | grep -c 'failed:' || true)"
assert_eq 1 "$fail_count" 'exactly one failure' && end_test_ok

# --- continue ---
begin_test 'align --on-failure continue: processes all refs'
local out2 rc2=0
out2="$(bash "$SCRIPT_UNDER_TEST" align --on-failure continue --subset missing origin upstream </dev/null 2>&1)" || rc2=$?
assert_status 1 "$rc2" 'should fail'
# Two "failed:" lines (one per branch)
local fail_count2
fail_count2="$(echo "$out2" | grep -c 'failed:' || true)"
assert_eq 2 "$fail_count2" 'two failures' && end_test_ok

# --- interactive non-tty ---
begin_test 'align --on-failure interactive: non-tty records failure with non-interactive label'
local out3 rc3=0
out3="$(bash "$SCRIPT_UNDER_TEST" align --on-failure interactive --subset missing origin upstream </dev/null 2>&1)" || rc3=$?
assert_contains "$out3" 'non-interactive' && end_test_ok

# --- invalid --on-failure value ---
begin_test 'align: invalid --on-failure value rejected'
local rc4=0
bash "$SCRIPT_UNDER_TEST" align --on-failure bogus origin upstream &>/dev/null || rc4=$?
assert_status 1 "$rc4" && end_test_ok

# --- --force and --force-with-lease mutually exclusive ---
begin_test 'align: --force and --force-with-lease mutually exclusive'
local rc5=0
bash "$SCRIPT_UNDER_TEST" align --force --force-with-lease origin upstream &>/dev/null || rc5=$?
assert_status 1 "$rc5" && end_test_ok

# --- same rejected for align ---
begin_test 'align: --subset same rejected'
local rc6=0
bash "$SCRIPT_UNDER_TEST" align --subset same origin upstream &>/dev/null || rc6=$?
assert_status 1 "$rc6" && end_test_ok

# --- different rejected for branch align ---
begin_test 'align: --subset different rejected for branches'
local rc7=0
bash "$SCRIPT_UNDER_TEST" align --subset different origin upstream &>/dev/null || rc7=$?
assert_status 1 "$rc7" && end_test_ok

# --- @ prefix rejected ---
begin_test 'align: @ prefix rejected'
local rc7=0
bash "$SCRIPT_UNDER_TEST" align "@${bare_a}" "@${bare_b}" &>/dev/null || rc7=$?
assert_status 1 "$rc7" && end_test_ok

# --- not exactly 2 remotes ---
begin_test 'align: fewer than two args rejected'
local rc9=0
bash "$SCRIPT_UNDER_TEST" align origin &>/dev/null || rc9=$?
assert_status 1 "$rc9" && end_test_ok

report_results
}
run_tests
