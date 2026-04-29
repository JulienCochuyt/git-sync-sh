#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/tests/helpers/env.sh"
source "${SCRIPT_DIR}/tests/helpers/assert.sh"
source "${SCRIPT_DIR}/tests/helpers/git-fixtures.sh"

setup_tmp

# Build fixture: work repo + two bare remotes with tags.
# Source = @bare_a (ls-remote), Target = @bare_b (ls-remote).
# Tags in source (bare_a) and target (bare_b) are set up to produce
# missing, new, and different categories.
work="${TEST_TMPDIR}/work"
bare_a="${TEST_TMPDIR}/origin.git"
bare_b="${TEST_TMPDIR}/upstream.git"

create_bare_remote "$bare_a"
create_bare_remote "$bare_b"
create_work_repo "$work"
add_and_fetch "$work" origin "$bare_a"
add_and_fetch "$work" upstream "$bare_b"

hash_base=$(make_commit "$work" 'base')
hash_other=$(make_commit "$work" 'other')

# Push all commits to both remotes so they have the objects available
git -C "$work" push origin main
git -C "$work" push upstream main

# missing_tag: in source (bare_a) but NOT in target (bare_b)
git -C "$bare_a" tag missing_tag "$hash_base"

# diff_tag: in source (bare_a) at hash_base, in target (bare_b) at hash_other
git -C "$bare_a" tag diff_tag "$hash_base"
git -C "$bare_b" tag diff_tag "$hash_other"

# new_tag: only in target (bare_b), NOT in source (bare_a)
git -C "$bare_b" tag new_tag "$hash_base"

cd "$work"

run_tests() {

# Plain remote names — align -t always queries via ls-remote.
local src="${bare_a}"
local tgt="${bare_b}"

begin_test 'align -t: missing tag pushed to target (dry-run)'
local out
out="$(bash "$SCRIPT_UNDER_TEST" align -t -n "$src" "$tgt" </dev/null 2>&1)"
assert_contains "$out" 'missing' \
	&& assert_contains "$out" 'missing_tag' \
	&& assert_contains "$out" 'to push' \
	&& end_test_ok

begin_test 'align -t: new tag delete in dry-run'
local out2
out2="$(bash "$SCRIPT_UNDER_TEST" align -t -n --subset +new "$src" "$tgt" </dev/null 2>&1)"
assert_contains "$out2" 'new' \
	&& assert_contains "$out2" 'delete' \
	&& assert_contains "$out2" 'new_tag' \
	&& end_test_ok

begin_test 'align -t: different tag included by default'
local out3
out3="$(bash "$SCRIPT_UNDER_TEST" align -t -n "$src" "$tgt" </dev/null 2>&1)"
assert_contains "$out3" 'different' \
	&& assert_contains "$out3" 'diff_tag' \
	&& end_test_ok

begin_test 'align -t: empty result'
local out4
out4="$(bash "$SCRIPT_UNDER_TEST" align -t -n --subset missing --exclude '*' "$src" "$tgt" </dev/null 2>&1)"
assert_contains "$out4" 'No tags to align.' && end_test_ok

begin_test 'align -t: direction categories rejected with tags'
local rc=0
bash "$SCRIPT_UNDER_TEST" align -t --subset behind "$src" "$tgt" &>/dev/null </dev/null || rc=$?
assert_status 1 "$rc" && end_test_ok

begin_test 'align -t: --subset ahead rejected with tags'
local rc_ahead=0
bash "$SCRIPT_UNDER_TEST" align -t --subset ahead "$src" "$tgt" &>/dev/null </dev/null || rc_ahead=$?
assert_status 1 "$rc_ahead" && end_test_ok

begin_test 'align -t: --subset diverged rejected with tags'
local rc_div=0
bash "$SCRIPT_UNDER_TEST" align -t --subset diverged "$src" "$tgt" &>/dev/null </dev/null || rc_div=$?
assert_status 1 "$rc_div" && end_test_ok

begin_test 'align -t: same rejected for align'
local rc2=0
bash "$SCRIPT_UNDER_TEST" align -t --subset same "$src" "$tgt" &>/dev/null </dev/null || rc2=$?
assert_status 1 "$rc2" && end_test_ok

begin_test 'align -t: @ prefix rejected'
local rc_at=0
bash "$SCRIPT_UNDER_TEST" align -t "@${bare_a}" "@${bare_b}" &>/dev/null </dev/null || rc_at=$?
assert_status 1 "$rc_at" && end_test_ok

report_results
}
run_tests
