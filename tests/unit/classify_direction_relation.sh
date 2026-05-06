#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/tests/helpers/env.sh"
source "${SCRIPT_DIR}/tests/helpers/assert.sh"
source "${SCRIPT_DIR}/tests/helpers/git-fixtures.sh"
source "$SCRIPT_UNDER_TEST"

setup_tmp

# Build a small commit graph:
#   A -- B -- C  (main, feature)
#            \
#             D  (diverge)
# B is ancestor of C; C is not ancestor of D; B is ancestor of D.

work="${TEST_TMPDIR}/repo"
create_work_repo "$work"
hash_a=$(make_commit "$work" 'A')
hash_b=$(make_commit "$work" 'B')

# branch at B
create_branch "$work" 'base' "$hash_b"

hash_c=$(make_commit "$work" 'C')
main_tip="$hash_c"

# diverge from B
git -C "$work" checkout -b diverge "$hash_b" >/dev/null 2>&1
hash_d=$(make_commit "$work" 'D')
git -C "$work" checkout main >/dev/null 2>&1

cd "$work"

begin_test 'behind: target is ancestor of source'
out="$(classify_direction_relation "$main_tip" "$hash_b")"
assert_eq 'behind' "$out" && end_test_ok

begin_test 'ahead: source is ancestor of target'
out="$(classify_direction_relation "$hash_b" "$main_tip")"
assert_eq 'ahead' "$out" && end_test_ok

begin_test 'diverged: neither is ancestor'
out="$(classify_direction_relation "$main_tip" "$hash_d")"
assert_eq 'diverged' "$out" && end_test_ok

begin_test 'identical hashes: behind (self is ancestor)'
out="$(classify_direction_relation "$hash_b" "$hash_b")"
assert_eq 'behind' "$out" 'same commit: b is ancestor of b' && end_test_ok

begin_test 'ahead-only mode: ahead detected (A ancestor of B)'
out="$(classify_direction_relation "$hash_b" "$main_tip" ahead-only)"
assert_eq 'ahead' "$out" && end_test_ok

begin_test 'ahead-only mode: non-ahead falls to different'
out="$(classify_direction_relation "$main_tip" "$hash_b" ahead-only)"
assert_eq 'different' "$out" && end_test_ok

begin_test 'ahead-only mode: diverged falls to different'
out="$(classify_direction_relation "$main_tip" "$hash_d" ahead-only)"
assert_eq 'different' "$out" && end_test_ok

begin_test 'ahead-only mode: unknown hash returns different'
out="$(classify_direction_relation "0000000000000000000000000000000000000000" "$main_tip" ahead-only)"
assert_eq 'different' "$out" && end_test_ok

begin_test 'behind-only mode: behind detected (B ancestor of A)'
out="$(classify_direction_relation "$main_tip" "$hash_b" behind-only)"
assert_eq 'behind' "$out" && end_test_ok

begin_test 'behind-only mode: non-behind falls to different'
out="$(classify_direction_relation "$hash_b" "$main_tip" behind-only)"
assert_eq 'different' "$out" && end_test_ok

begin_test 'behind-only mode: diverged falls to different'
out="$(classify_direction_relation "$main_tip" "$hash_d" behind-only)"
assert_eq 'different' "$out" && end_test_ok

begin_test 'behind-only mode: unknown hash returns different'
out="$(classify_direction_relation "$main_tip" "0000000000000000000000000000000000000000" behind-only)"
assert_eq 'different' "$out" && end_test_ok

begin_test 'full mode: unknown hash returns unrelated (no merge-base reachable)'
out="$(classify_direction_relation "$main_tip" "0000000000000000000000000000000000000000" full)"
assert_eq 'unrelated' "$out" && end_test_ok

# --- unrelated: two disjoint repos sharing object DB ---
# Build a second repo with no shared root, then fetch its tip into the
# main test repo so both commits are reachable here without sharing
# any common ancestor.
other="${TEST_TMPDIR}/other_repo"
git init -b main "$other" >/dev/null 2>&1
git -C "$other" commit --allow-empty -m 'O1' >/dev/null 2>&1
git -C "$other" commit --allow-empty -m 'O2' >/dev/null 2>&1
hash_o=$(git -C "$other" rev-parse HEAD)
git -C "$work" fetch "$other" "$hash_o:refs/git-sync-test/other" >/dev/null 2>&1

begin_test 'full mode: unrelated histories detected via merge-base failure'
out="$(classify_direction_relation "$main_tip" "$hash_o" full)"
assert_eq 'unrelated' "$out" && end_test_ok

begin_test 'full mode: unrelated is symmetric'
out="$(classify_direction_relation "$hash_o" "$main_tip" full)"
assert_eq 'unrelated' "$out" && end_test_ok

begin_test 'ahead-only mode: unrelated falls to different'
out="$(classify_direction_relation "$main_tip" "$hash_o" ahead-only)"
assert_eq 'different' "$out" && end_test_ok

begin_test 'behind-only mode: unrelated falls to different'
out="$(classify_direction_relation "$main_tip" "$hash_o" behind-only)"
assert_eq 'different' "$out" && end_test_ok

report_results
