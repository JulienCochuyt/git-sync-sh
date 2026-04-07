#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/tests/helpers/env.sh"
source "${SCRIPT_DIR}/tests/helpers/assert.sh"
source "${SCRIPT_DIR}/tests/helpers/git-fixtures.sh"

setup_tmp

# Build fixture with direction-testable commit graph.
work="${TEST_TMPDIR}/work"
bare_a="${TEST_TMPDIR}/origin.git"
bare_b="${TEST_TMPDIR}/upstream.git"

create_bare_remote "$bare_a"
create_bare_remote "$bare_b"
create_work_repo "$work"
add_and_fetch "$work" origin "$bare_a"
add_and_fetch "$work" upstream "$bare_b"

# base commit on main
hash_base=$(make_commit "$work" 'base')

# behind_br: upstream is behind origin (origin has extra commit)
create_branch "$work" behind_br "$hash_base"
push_branch "$work" upstream behind_br
hash_ahead_of_base=$(make_commit "$work" 'ahead-of-base')
create_branch "$work" behind_br "$hash_ahead_of_base"
push_branch "$work" origin behind_br
git -C "$work" checkout main >/dev/null 2>&1

# ahead_br: upstream is ahead of origin (upstream has extra commit)
create_branch "$work" ahead_br "$hash_base"
push_branch "$work" origin ahead_br
hash_ahead2=$(make_commit "$work" 'ahead2')
create_branch "$work" ahead_br "$hash_ahead2"
push_branch "$work" upstream ahead_br
git -C "$work" checkout main >/dev/null 2>&1

# diverged_br: diverged histories (both sides have commits the other doesn't)
git -C "$work" checkout -b divtmp_a "$hash_base" >/dev/null 2>&1
hash_div_a=$(make_commit "$work" 'div-a')
create_branch "$work" diverged_br "$hash_div_a"
push_branch "$work" origin diverged_br
git -C "$work" checkout -b divtmp_b "$hash_base" >/dev/null 2>&1
hash_div_b=$(make_commit "$work" 'div-b')
create_branch "$work" diverged_br "$hash_div_b"
push_branch "$work" upstream diverged_br
git -C "$work" checkout main >/dev/null 2>&1

# same_br: identical on both
create_branch "$work" same_br "$hash_base"
push_branch "$work" origin same_br
push_branch "$work" upstream same_br

git -C "$work" fetch origin --prune >/dev/null 2>&1
git -C "$work" fetch upstream --prune >/dev/null 2>&1

cd "$work"

run_tests() {

# --- Direction auto-detection ---
begin_test 'status: behind section shown'
local out
out="$(bash "$SCRIPT_UNDER_TEST" status origin upstream)"
assert_contains "$out" 'Behind:' \
	&& assert_contains "$out" 'behind_br' \
	&& end_test_ok

begin_test 'status: ahead section shown'
local out2
out2="$(bash "$SCRIPT_UNDER_TEST" status origin upstream)"
assert_contains "$out2" 'Ahead:' \
	&& assert_contains "$out2" 'ahead_br' \
	&& end_test_ok

begin_test 'status: diverged section shown'
local out3
out3="$(bash "$SCRIPT_UNDER_TEST" status origin upstream)"
assert_contains "$out3" 'Diverged:' \
	&& assert_contains "$out3" 'diverged_br' \
	&& end_test_ok

begin_test 'status: no Different section with two local remotes'
local out4
out4="$(bash "$SCRIPT_UNDER_TEST" status origin upstream)"
assert_not_contains "$out4" 'Different:' && end_test_ok

# --- Direction porcelain ---
begin_test 'status -p: porcelain shows behind/ahead/diverged categories'
local out5
out5="$(bash "$SCRIPT_UNDER_TEST" status -p origin upstream)"
assert_contains "$out5" 'behind' \
	&& assert_contains "$out5" 'ahead' \
	&& assert_contains "$out5" 'diverged' \
	&& assert_not_contains "$out5" 'different' \
	&& end_test_ok

# --- Direction name-only ---
begin_test 'status --name-only: shows ref names for directional categories'
local out6
out6="$(bash "$SCRIPT_UNDER_TEST" status --name-only origin upstream)"
assert_contains "$out6" 'behind_br' \
	&& assert_contains "$out6" 'ahead_br' \
	&& assert_contains "$out6" 'diverged_br' \
	&& end_test_ok

# --- Subset implies direction ---
begin_test 'status --subset behind: shows only behind branches'
local out7
out7="$(bash "$SCRIPT_UNDER_TEST" status --name-only --subset behind origin upstream)"
assert_contains "$out7" 'behind_br' \
	&& assert_not_contains "$out7" 'ahead_br' \
	&& assert_not_contains "$out7" 'diverged_br' \
	&& end_test_ok

# --- Mutually exclusive options ---
begin_test 'status: --name-only and --porcelain mutually exclusive'
local rc=0
bash "$SCRIPT_UNDER_TEST" status --name-only -p origin upstream &>/dev/null || rc=$?
assert_status 1 "$rc" && end_test_ok

# --- --subset different rejected with two local remotes ---
begin_test 'status: --subset different rejected with two local remotes'
local rc_diff=0
bash "$SCRIPT_UNDER_TEST" status --subset different origin upstream &>/dev/null || rc_diff=$?
assert_status 1 "$rc_diff" && end_test_ok

# --- Exactly two remotes required ---
begin_test 'status: zero args with multiple remotes and no upstream rejected'
local rc4=0
bash "$SCRIPT_UNDER_TEST" status &>/dev/null || rc4=$?
assert_status 1 "$rc4" && end_test_ok

begin_test 'status: more than two remotes rejected'
local rc5=0
bash "$SCRIPT_UNDER_TEST" status origin upstream extra &>/dev/null || rc5=$?
assert_status 1 "$rc5" && end_test_ok

# --- Combined short options ---
begin_test 'status: -pa rejected (--all not supported with --porcelain)'
local rc_pa=0
bash "$SCRIPT_UNDER_TEST" status -pa origin upstream &>/dev/null || rc_pa=$?
assert_status 1 "$rc_pa" && end_test_ok

begin_test 'status: --all --name-only rejected'
local rc_ano=0
bash "$SCRIPT_UNDER_TEST" status --all --name-only origin upstream &>/dev/null || rc_ano=$?
assert_status 1 "$rc_ano" && end_test_ok

begin_test 'status: -ps behind expands to -p -s behind'
local combo_ps
combo_ps="$(bash "$SCRIPT_UNDER_TEST" status -ps behind origin upstream)"
local sep_ps
sep_ps="$(bash "$SCRIPT_UNDER_TEST" status -p -s behind origin upstream)"
assert_eq "$combo_ps" "$sep_ps" '-ps matches -p -s' && end_test_ok

begin_test 'status: -ta works (combined flag + flag)'
local combo_ta
combo_ta="$(bash "$SCRIPT_UNDER_TEST" status -ta @origin @upstream)"
local sep_ta
sep_ta="$(bash "$SCRIPT_UNDER_TEST" status -t -a @origin @upstream)"
assert_eq "$combo_ta" "$sep_ta" '-ta matches -t -a' && end_test_ok

# --- Porcelain tab-separated format ---
begin_test 'status -p: tab-separated columns'
local out8
out8="$(bash "$SCRIPT_UNDER_TEST" status -p origin upstream)"
local first_line
first_line="$(echo "$out8" | head -1)"
local tab_count
tab_count="$(echo "$first_line" | tr -cd '\t' | wc -c)"
assert_eq 5 "$tab_count" '6 columns = 5 tabs' && end_test_ok

report_results
}
run_tests
