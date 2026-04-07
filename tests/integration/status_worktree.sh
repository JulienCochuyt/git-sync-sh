#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/tests/helpers/env.sh"
source "${SCRIPT_DIR}/tests/helpers/assert.sh"
source "${SCRIPT_DIR}/tests/helpers/git-fixtures.sh"

setup_tmp

# Build fixture: work repo + one bare remote (origin).
# The working copy has local branches compared against origin's tracking refs.
work="${TEST_TMPDIR}/work"
bare_origin="${TEST_TMPDIR}/origin.git"

create_bare_remote "$bare_origin"
create_work_repo "$work"
add_and_fetch "$work" origin "$bare_origin"

# Push main to origin so it exists on both sides
push_branch "$work" origin main

# same_br: identical on working copy and origin
hash_base=$(make_commit "$work" 'base')
create_branch "$work" same_br "$hash_base"
push_branch "$work" origin same_br

# ahead_br: local is ahead of origin (local has extra commit)
create_branch "$work" ahead_br "$hash_base"
push_branch "$work" origin ahead_br
hash_ahead=$(make_commit "$work" 'ahead-extra')
create_branch "$work" ahead_br "$hash_ahead"

# behind_br: local is behind origin (origin has extra commit)
hash_behind_extra=$(make_commit "$work" 'behind-extra')
create_branch "$work" behind_br "$hash_behind_extra"
push_branch "$work" origin behind_br
# reset local behind_br to the base (so local is behind)
create_branch "$work" behind_br "$hash_base"

# local_only_br: exists only locally (missing from origin)
create_branch "$work" local_only_br "$hash_base"

# remote_only_br: exists only on origin (new in B)
create_branch "$work" remote_only_br "$hash_base"
push_branch "$work" origin remote_only_br
# delete the local branch
git -C "$work" branch -D remote_only_br >/dev/null 2>&1

# Fetch to update tracking refs
git -C "$work" fetch origin --prune >/dev/null 2>&1

cd "$work"

run_tests() {

# --- Single-argument mode: branches ---
begin_test 'status: single-arg shows direction for local branches'
local out
out="$(bash "$SCRIPT_UNDER_TEST" status origin)"
assert_contains "$out" 'Behind:' \
	&& assert_contains "$out" 'behind_br' \
	&& assert_contains "$out" 'Ahead:' \
	&& assert_contains "$out" 'ahead_br' \
	&& end_test_ok

begin_test 'status: single-arg shows missing (local-only branch)'
local out2
out2="$(bash "$SCRIPT_UNDER_TEST" status origin)"
assert_contains "$out2" 'Missing: only in working copy' \
	&& assert_contains "$out2" 'local_only_br' \
	&& end_test_ok

begin_test 'status: single-arg expands new by default when few'
local out3
out3="$(bash "$SCRIPT_UNDER_TEST" status origin)"
assert_contains "$out3" 'New: only in origin (1)' \
	&& assert_contains "$out3" 'remote_only_br' \
	&& end_test_ok

begin_test 'status: single-arg --all shows new details'
# Note: with only 1 new ref, threshold expansion (test above) produces the
# same result.  --all is tested distinctly because it bypasses thresholds.
local out4
out4="$(bash "$SCRIPT_UNDER_TEST" status --all origin)"
assert_contains "$out4" 'New: only in origin' \
	&& assert_contains "$out4" 'remote_only_br' \
	&& end_test_ok

begin_test 'status: single-arg --subset new shows new details'
local out5
out5="$(bash "$SCRIPT_UNDER_TEST" status --subset new origin)"
assert_contains "$out5" 'remote_only_br' && end_test_ok

begin_test 'status: single-arg porcelain includes new'
local out6
out6="$(bash "$SCRIPT_UNDER_TEST" status -p origin)"
assert_contains "$out6" 'new' \
	&& assert_contains "$out6" 'remote_only_br' \
	&& end_test_ok

begin_test 'status: single-arg identical branches expanded when few'
local out7
out7="$(bash "$SCRIPT_UNDER_TEST" status origin)"
assert_contains "$out7" 'Same: identical in working copy and origin' \
	&& assert_contains "$out7" 'same_br' \
	&& end_test_ok

begin_test 'status: single-arg --name-only includes all categories'
local out8
out8="$(bash "$SCRIPT_UNDER_TEST" status --name-only origin)"
assert_contains "$out8" 'remote_only_br' \
	&& assert_contains "$out8" 'local_only_br' \
	&& assert_contains "$out8" 'ahead_br' \
	&& assert_contains "$out8" 'same_br' \
	&& end_test_ok

# --- Single-argument mode: tags ---
begin_test 'status: single-arg -t with @remote works'
local out_tags
out_tags="$(bash "$SCRIPT_UNDER_TEST" status -t "@${bare_origin}" 2>&1)" || true
# Should not error (may have no tags to report, that's fine)
assert_not_contains "$out_tags" 'Invalid' && end_test_ok

begin_test 'status: single-arg -t with plain remote works'
local out_tags_plain
out_tags_plain="$(bash "$SCRIPT_UNDER_TEST" status -t origin 2>&1)" || true
assert_not_contains "$out_tags_plain" 'Invalid' && end_test_ok

# --- @remote single argument: behind-only direction ---
begin_test 'status: single-arg @remote uses behind-only direction'
local out_remote
out_remote="$(bash "$SCRIPT_UNDER_TEST" status "@${bare_origin}")"
assert_contains "$out_remote" 'Behind:' \
	&& assert_contains "$out_remote" 'Different:' \
	&& assert_not_contains "$out_remote" 'Ahead:' \
	&& end_test_ok

begin_test 'status: single-arg @remote behind-only classifies correctly'
# In behind-only mode (worktree=local, target=@remote), only "behind" (B ancestor
# of A) is reliably detectable.  ahead_br has worktree ahead of origin, so origin
# is an ancestor of worktree → classified as behind.
local out_behind
out_behind="$(bash "$SCRIPT_UNDER_TEST" status --name-only --subset behind "@${bare_origin}")"
assert_contains "$out_behind" 'ahead_br' && end_test_ok

# --- Zero-argument mode ---
begin_test 'status: zero-arg resolves sole remote'
local out_zero
out_zero="$(bash "$SCRIPT_UNDER_TEST" status)"
assert_contains "$out_zero" 'working copy' \
	&& assert_contains "$out_zero" 'origin' \
	&& end_test_ok

begin_test 'status: zero-arg with upstream configured'
git -C "$work" branch --set-upstream-to=origin/main main >/dev/null 2>&1
local out_upstream
out_upstream="$(bash "$SCRIPT_UNDER_TEST" status)"
assert_contains "$out_upstream" 'working copy' \
	&& assert_contains "$out_upstream" 'origin' \
	&& end_test_ok

report_results
}
run_tests
