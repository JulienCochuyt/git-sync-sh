#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/tests/helpers/env.sh"
source "${SCRIPT_DIR}/tests/helpers/assert.sh"
source "${SCRIPT_DIR}/tests/helpers/git-fixtures.sh"

setup_tmp

# Build fixture: work repo + two bare remotes (origin, upstream).
work="${TEST_TMPDIR}/work"
bare_a="${TEST_TMPDIR}/origin.git"
bare_b="${TEST_TMPDIR}/upstream.git"

create_bare_remote "$bare_a"
create_bare_remote "$bare_b"
create_work_repo "$work"
add_and_fetch "$work" origin "$bare_a"
add_and_fetch "$work" upstream "$bare_b"

# shared: same commit on both
hash_shared=$(make_commit "$work" 'shared')
create_branch "$work" shared "$hash_shared"
push_branch "$work" origin shared
push_branch "$work" upstream shared
git -C "$work" fetch origin --prune >/dev/null 2>&1
git -C "$work" fetch upstream --prune >/dev/null 2>&1

# only_origin: exists only in origin (missing from upstream)
create_branch "$work" only_origin "$hash_shared"
push_branch "$work" origin only_origin
git -C "$work" fetch origin --prune >/dev/null 2>&1

# only_upstream: exists only in upstream (new in upstream)
create_branch "$work" only_upstream "$hash_shared"
push_branch "$work" upstream only_upstream
git -C "$work" fetch upstream --prune >/dev/null 2>&1

# diff_branch: different hashes on each side
create_branch "$work" diff_branch "$hash_shared"
push_branch "$work" origin diff_branch
hash_diff2=$(make_commit "$work" 'diff2')
create_branch "$work" diff_branch "$hash_diff2"
push_branch "$work" upstream diff_branch
git -C "$work" fetch origin --prune >/dev/null 2>&1
git -C "$work" fetch upstream --prune >/dev/null 2>&1

# Also push main to both
push_branch "$work" origin main
push_branch "$work" upstream main
git -C "$work" fetch origin --prune >/dev/null 2>&1
git -C "$work" fetch upstream --prune >/dev/null 2>&1

cd "$work"

run_tests() {

begin_test 'status: missing branch (only in source)'
local out
out="$(bash "$SCRIPT_UNDER_TEST" status origin upstream)"
assert_contains "$out" 'Missing: only in origin' && end_test_ok

begin_test 'status: new branch (only in target)'
local out2
out2="$(bash "$SCRIPT_UNDER_TEST" status origin upstream)"
assert_contains "$out2" 'New: only in upstream' && end_test_ok

begin_test 'status: ahead branch (upstream ahead of origin)'
local out3
out3="$(bash "$SCRIPT_UNDER_TEST" status origin upstream)"
assert_contains "$out3" 'Ahead: upstream ahead of origin' && end_test_ok

begin_test 'status: identical branches expanded by default when few'
local out4
out4="$(bash "$SCRIPT_UNDER_TEST" status origin upstream)"
assert_contains "$out4" 'Same: identical in origin and upstream' \
	&& assert_contains "$out4" 'main' \
	&& assert_contains "$out4" 'shared' \
	&& end_test_ok

begin_test 'status: --all shows identical branches'
# Note: with only 2 same branches, threshold expansion (test above) produces
# the same result.  --all is tested distinctly because it bypasses thresholds.
local out5
out5="$(bash "$SCRIPT_UNDER_TEST" status --all origin upstream)"
assert_contains "$out5" 'Same: identical in origin and upstream' \
	&& assert_contains "$out5" 'main' \
	&& assert_contains "$out5" 'shared' \
	&& end_test_ok

begin_test 'status: porcelain output contains all categories'
local out6
out6="$(bash "$SCRIPT_UNDER_TEST" status -p origin upstream)"
assert_contains "$out6" 'missing' \
	&& assert_contains "$out6" 'new' \
	&& assert_contains "$out6" 'ahead' \
	&& assert_contains "$out6" 'same' \
	&& end_test_ok

begin_test 'status: name-only shows ref names without headers'
local out7
out7="$(bash "$SCRIPT_UNDER_TEST" status --name-only origin upstream)"
assert_contains "$out7" 'only_origin' \
	&& assert_contains "$out7" 'only_upstream' \
	&& assert_contains "$out7" 'diff_branch' \
	&& assert_contains "$out7" 'main' \
	&& assert_contains "$out7" 'shared' \
	&& assert_not_contains "$out7" 'Missing:' \
	&& end_test_ok

begin_test 'status: --include filters refs'
local out8
out8="$(bash "$SCRIPT_UNDER_TEST" status --name-only -i 'only_*' origin upstream)"
assert_contains "$out8" 'only_origin' \
	&& assert_contains "$out8" 'only_upstream' \
	&& assert_not_contains "$out8" 'diff_branch' \
	&& end_test_ok

begin_test 'status: --exclude removes refs'
local out9
out9="$(bash "$SCRIPT_UNDER_TEST" status --name-only -x 'diff_*' origin upstream)"
assert_not_contains "$out9" 'diff_branch' \
	&& assert_contains "$out9" 'only_origin' \
	&& end_test_ok

begin_test 'status: --subset missing shows only missing'
local out10
out10="$(bash "$SCRIPT_UNDER_TEST" status --name-only --subset missing origin upstream)"
assert_contains "$out10" 'only_origin' \
	&& assert_not_contains "$out10" 'only_upstream' \
	&& assert_not_contains "$out10" 'diff_branch' \
	&& end_test_ok

begin_test 'status: --subset same --porcelain shows identical refs (regression)'
local out11
out11="$(bash "$SCRIPT_UNDER_TEST" status -p --subset same origin upstream)"
assert_contains "$out11" 'same' \
	&& assert_contains "$out11" 'main' \
	&& assert_not_contains "$out11" 'missing' \
	&& end_test_ok

begin_test 'status: --subset same shows full list in human mode (regression)'
local out12
out12="$(bash "$SCRIPT_UNDER_TEST" status --subset same origin upstream)"
assert_contains "$out12" 'Same: identical in origin and upstream' \
	&& assert_not_contains "$out12" 'Use --all' \
	&& assert_contains "$out12" 'main' \
	&& end_test_ok

begin_test 'status: @remote queries via ls-remote'
local out13
out13="$(bash "$SCRIPT_UNDER_TEST" status --name-only "@$bare_a" "@$bare_b")"
assert_contains "$out13" 'only_origin' \
	&& assert_contains "$out13" 'only_upstream' \
	&& end_test_ok

begin_test 'status: empty result prints No branches to report'
local out14
out14="$(bash "$SCRIPT_UNDER_TEST" status --subset same --exclude '*' origin upstream)"
assert_contains "$out14" 'No branches to report.' && end_test_ok

begin_test 'status --all: does not print "No branches to report" when same branches exist'
local out_all_same
out_all_same="$(bash "$SCRIPT_UNDER_TEST" status --all origin upstream)"
assert_contains "$out_all_same" 'Same:' \
	&& assert_not_contains "$out_all_same" 'No branches to report' \
	&& end_test_ok

begin_test 'status: --subset +same adds same to human output'
local out15
out15="$(bash "$SCRIPT_UNDER_TEST" status --subset +same origin upstream)"
assert_contains "$out15" 'Same: identical in origin and upstream' \
	&& assert_contains "$out15" 'main' \
	&& assert_contains "$out15" 'shared' \
	&& assert_contains "$out15" 'only_origin' \
	&& assert_not_contains "$out15" 'Use --all' \
	&& end_test_ok

begin_test 'status: --subset -new removes new from output'
local out16
out16="$(bash "$SCRIPT_UNDER_TEST" status --name-only --subset -new origin upstream)"
assert_not_contains "$out16" 'only_upstream' \
	&& assert_contains "$out16" 'only_origin' \
	&& assert_contains "$out16" 'diff_branch' \
	&& end_test_ok

begin_test 'status: --subset -missing,-new shows only different'
local out17
out17="$(bash "$SCRIPT_UNDER_TEST" status --name-only --subset '-missing,-new,-ahead' origin upstream)"
assert_not_contains "$out17" 'only_origin' \
	&& assert_not_contains "$out17" 'only_upstream' \
	&& end_test_ok

report_results
}
run_tests
