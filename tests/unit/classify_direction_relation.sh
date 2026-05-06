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

# --- unknown vs unrelated in shallow clones ---
# Build a deep linear history with a divergent branch from an early
# commit, push both branches to a bare remote, then shallow-clone with
# --depth=2 into a fresh work repo. In the shallow clone:
#   - The actual merge-base of the two tips lies below the shallow
#     boundary, so `git merge-base` returns empty.
#   - Neither tip's ancestor walk reaches a parentless commit (both
#     are cut off by the shallow boundary).
# Expected verdict: `unknown` (ancestry inconclusive), not `unrelated`.
deep_work="${TEST_TMPDIR}/deep_work"
deep_bare="${TEST_TMPDIR}/deep.git"
shallow_work="${TEST_TMPDIR}/shallow_work"

git init --bare "$deep_bare" >/dev/null 2>&1
create_work_repo "$deep_work"
make_commit "$deep_work" 'L1' >/dev/null
hash_l2=$(make_commit "$deep_work" 'L2')
for _i in 3 4 5 6 7 8 9 10; do
	make_commit "$deep_work" "L${_i}" >/dev/null
done
git -C "$deep_work" checkout -b side "$hash_l2" >/dev/null 2>&1
make_commit "$deep_work" 'S1' >/dev/null
make_commit "$deep_work" 'S2' >/dev/null
make_commit "$deep_work" 'S3' >/dev/null
make_commit "$deep_work" 'S4' >/dev/null
make_commit "$deep_work" 'S5' >/dev/null
git -C "$deep_work" push "$deep_bare" 'main:refs/heads/main' >/dev/null 2>&1
git -C "$deep_work" push "$deep_bare" 'side:refs/heads/side' >/dev/null 2>&1

git clone --depth=2 --branch=main "$deep_bare" "$shallow_work" >/dev/null 2>&1
git -C "$shallow_work" fetch --depth=2 origin 'refs/heads/side:refs/git-sync-test/side' >/dev/null 2>&1

shallow_main=$(git -C "$shallow_work" rev-parse refs/remotes/origin/main)
shallow_side=$(git -C "$shallow_work" rev-parse refs/git-sync-test/side)

# Sanity: confirm we really are in a shallow repo.
[[ "$(git -C "$shallow_work" rev-parse --is-shallow-repository)" == 'true' ]] \
	|| { printf 'fixture broken: shallow_work is not shallow\n' >&2; exit 1; }

pushd "$shallow_work" >/dev/null

begin_test 'full mode: shallow repo, merge-base unreachable beyond depth -> unknown'
out="$(classify_direction_relation "$shallow_main" "$shallow_side" full)"
assert_eq 'unknown' "$out" 'shallow boundary cuts off the common ancestor' \
	&& end_test_ok

begin_test 'full mode: unknown is symmetric'
out="$(classify_direction_relation "$shallow_side" "$shallow_main" full)"
assert_eq 'unknown' "$out" && end_test_ok

# Genuinely-unrelated histories in a shallow clone: fetch a 1-commit
# tip from a separate `git init` repo. Its single commit has no
# parent, so `git rev-list --max-parents=0 --count` reports 1, and
# the verdict must remain `unrelated` even though we are inside a
# shallow clone.
tiny_other="${TEST_TMPDIR}/tiny_other"
git init -b main "$tiny_other" >/dev/null 2>&1
git -C "$tiny_other" commit --allow-empty -m 'tinyroot' >/dev/null 2>&1
hash_tiny=$(git -C "$tiny_other" rev-parse HEAD)
git -C "$shallow_work" fetch "$tiny_other" "$hash_tiny:refs/git-sync-test/tiny" >/dev/null 2>&1

begin_test 'full mode: shallow repo, one truncated + one anchored tip -> unknown'
out="$(classify_direction_relation "$shallow_main" "$hash_tiny" full)"
# shallow_main does NOT reach a root within the shallow window, so at
# least one tip is truncated -> unknown. Document this as the expected
# behaviour (we cannot tell apart truncated-vs-disjoint when one side
# is shallow).
assert_eq 'unknown' "$out" \
	'one truncated tip + one anchored tip is still unknown (no false unrelated)' \
	&& end_test_ok

popd >/dev/null

report_results
