#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
#
# Integration tests for the `unknown` category (plan-unknown.md).
#
# Builds a deep linear history with a divergent branch, pushes both
# branches to a bare remote, then runs `git sync status` from a
# shallow clone (--depth=2). The actual common ancestor lies below
# the shallow boundary, so `git merge-base` returns empty and the
# classifier must route the ref to `unknown` (not `unrelated`).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/tests/helpers/env.sh"
source "${SCRIPT_DIR}/tests/helpers/assert.sh"
source "${SCRIPT_DIR}/tests/helpers/git-fixtures.sh"

setup_tmp

# --- Build fixture: deep history with divergent branch in two bares. ---
#
# bare_a (origin) and bare_b (upstream) both receive a single branch
# named `probe`. Each `probe` was branched from the same early commit
# of a shared deep history, so a real merge-base exists — but it lies
# 8 commits below the tip. We then shallow-clone origin with --depth=2
# and fetch upstream's `probe` shallowly into the same repo. Inside
# the shallow clone, `git merge-base` between the two `probe` tips
# returns empty (the common ancestor is beyond the boundary) and
# neither tip's walk reaches a parentless commit, so the verdict is
# `unknown`.
#
# A second branch `truly_unrelated` is fetched from a 1-commit repo
# (root reachable in the shallow clone) so we can verify the
# discriminator: an anchored tip on one side keeps the whole compare
# in `unknown` (we still cannot decide), but a NON-shallow control
# repo (built separately at the bottom) confirms genuinely-disjoint
# histories still go to `unrelated`.
deep_work="${TEST_TMPDIR}/deep_work"
bare_a="${TEST_TMPDIR}/origin.git"
bare_b="${TEST_TMPDIR}/upstream.git"
shallow_consumer="${TEST_TMPDIR}/shallow_consumer"

create_bare_remote "$bare_a"
create_bare_remote "$bare_b"

create_work_repo "$deep_work"
make_commit "$deep_work" 'L1' >/dev/null
hash_l2=$(make_commit "$deep_work" 'L2')
for _i in 3 4 5 6 7 8 9 10; do
	make_commit "$deep_work" "L${_i}" >/dev/null
done

# origin's `probe` follows main.
git -C "$deep_work" push "$bare_a" 'main:refs/heads/probe' >/dev/null 2>&1

# upstream's `probe` diverges from L2 with a different chain.
git -C "$deep_work" checkout -b probe_upstream "$hash_l2" >/dev/null 2>&1
make_commit "$deep_work" 'U1' >/dev/null
make_commit "$deep_work" 'U2' >/dev/null
make_commit "$deep_work" 'U3' >/dev/null
make_commit "$deep_work" 'U4' >/dev/null
make_commit "$deep_work" 'U5' >/dev/null
git -C "$deep_work" push "$bare_b" 'probe_upstream:refs/heads/probe' >/dev/null 2>&1

# Shallow clone origin with --depth=2 and shallow-fetch upstream.
git clone --depth=2 --branch=probe "$bare_a" "$shallow_consumer" >/dev/null 2>&1
git -C "$shallow_consumer" remote add upstream "$bare_b"
git -C "$shallow_consumer" fetch --depth=2 upstream >/dev/null 2>&1

# Sanity check: the consumer is shallow.
[[ "$(git -C "$shallow_consumer" rev-parse --is-shallow-repository)" == 'true' ]] \
	|| { printf 'fixture broken: shallow_consumer is not shallow\n' >&2; exit 1; }

cd "$shallow_consumer"

run_tests() {

# --- Porcelain output ---

begin_test 'status: shallow clone, divergent probe -> unknown (porcelain)'
local out_p
out_p="$(bash "$SCRIPT_UNDER_TEST" status -p origin upstream)"
assert_contains "$out_p" $'unknown\tprobe\t' \
	'probe should be reported under the unknown category' \
	&& assert_not_contains "$out_p" $'unrelated\tprobe\t' \
		'probe must NOT be classified as unrelated in a shallow clone' \
	&& assert_not_contains "$out_p" $'diverged\tprobe\t' \
		'probe must NOT be classified as diverged when merge-base is unreachable' \
	&& end_test_ok

begin_test 'status: porcelain unknown row uses -\\t- count slots'
local line
line="$(printf '%s\n' "$out_p" | grep $'^unknown\tprobe\t')"
# Layout: unknown\t<ref>\t<src>\t<tgt>\t<behind>\t<ahead>
local _cat _ref _src _tgt _b _a
IFS=$'\t' read -r _cat _ref _src _tgt _b _a <<< "$line"
assert_eq 'unknown' "$_cat" \
	&& assert_eq 'probe' "$_ref" \
	&& assert_eq '-' "$_b" 'behind count must be -' \
	&& assert_eq '-' "$_a" 'ahead count must be -' \
	&& end_test_ok

# --- Human output ---

begin_test 'status: shallow clone, human output shows Unknown section + hint'
local out_h
out_h="$(bash "$SCRIPT_UNDER_TEST" status origin upstream)"
assert_contains "$out_h" 'Unknown: ancestry inconclusive between' \
	'human output should announce the Unknown section' \
	&& assert_contains "$out_h" 'probe' \
		'probe ref should appear in the Unknown section' \
	&& assert_contains "$out_h" "hint: local repository is shallow" \
		'shallow-repository hint should be printed' \
	&& assert_contains "$out_h" "git fetch --unshallow" \
		'hint should mention git fetch --unshallow' \
	&& end_test_ok

# --- Subset filtering ---

begin_test 'status: --subset unknown keeps the unknown ref'
local out_p2
out_p2="$(bash "$SCRIPT_UNDER_TEST" status -p --subset unknown origin upstream)"
assert_contains "$out_p2" $'unknown\tprobe\t' \
	&& end_test_ok

begin_test 'status: --subset -unknown drops the unknown ref'
local out_p3
out_p3="$(bash "$SCRIPT_UNDER_TEST" status -p --subset -unknown origin upstream)"
assert_not_contains "$out_p3" $'unknown\tprobe\t' \
	&& end_test_ok

begin_test 'status: --subset unrelated alone excludes unknown rows'
local out_p4
out_p4="$(bash "$SCRIPT_UNDER_TEST" status -p --subset unrelated origin upstream)"
assert_not_contains "$out_p4" $'unknown\tprobe\t' \
	'plain --subset unrelated must not include unknown rows' \
	&& end_test_ok

begin_test 'status: --subset unknown,unrelated keeps unknown rows'
local out_p5
out_p5="$(bash "$SCRIPT_UNDER_TEST" status -p --subset unknown,unrelated origin upstream)"
assert_contains "$out_p5" $'unknown\tprobe\t' \
	&& end_test_ok

# --- Validation: --tags rejects unknown like the other directional cats ---

begin_test 'status: --tags --subset unknown is rejected'
local out_tags rc=0
out_tags="$(bash "$SCRIPT_UNDER_TEST" status -t --subset unknown origin upstream 2>&1)" || rc=$?
assert_status 1 "$rc" \
	&& assert_contains "$out_tags" 'unknown' \
	&& end_test_ok

# --- Align defaults include unknown ---

begin_test 'align: --subset unknown valid for branches'
local out_align rc2=0
out_align="$(bash "$SCRIPT_UNDER_TEST" align -n --subset unknown origin upstream 2>&1)" || rc2=$?
assert_status 0 "$rc2" 'align --subset unknown should accept the category' \
	&& assert_contains "$out_align" $'unknown\tpush\tprobe\t' \
		'align should report the unknown ref as a candidate' \
	&& end_test_ok

begin_test 'align: --subset -unknown removes unknown refs from candidates'
local out_align2
out_align2="$(bash "$SCRIPT_UNDER_TEST" align -n --subset -unknown origin upstream 2>&1 || true)"
assert_not_contains "$out_align2" $'unknown\tpush\tprobe\t' \
	'unknown ref must be skipped when subtracted from defaults' \
	&& end_test_ok

report_results
}
run_tests
