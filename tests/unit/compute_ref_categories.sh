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

# Build a simple graph for direction tests.
work="${TEST_TMPDIR}/repo"
create_work_repo "$work"
base=$(make_commit "$work" 'base')
tip=$(make_commit "$work" 'tip')

git -C "$work" checkout -b side "$base" >/dev/null 2>&1
side_tip=$(make_commit "$work" 'side')
git -C "$work" checkout main >/dev/null 2>&1

cd "$work"

run_tests() {

# Helper: extract refs from a refs_by_cat value into a named array.
rbc_to_array() {
	local -n _rbc_out="$1"
	_rbc_out=()
	if [[ -n "$2" ]]; then
		mapfile -t _rbc_out <<< "$2"
	fi
}

local -a _m=() _n=() _d=() _b=() _a=() _v=() _s=()

# --- No direction mode ---
begin_test 'compute: missing, new, different, same (no direction)'
declare -A src=([shared]="$base" [only_src]="$base" [diff]="$base")
declare -A tgt=([shared]="$base" [only_tgt]="$tip" [diff]="$tip")
local -a inc=('' '' '') exc=('' '' '') re=(0 0 0)
declare -A rbc=() bc=() ac=()

compute_ref_categories src tgt 'none' inc exc re rbc bc ac

rbc_to_array _m "${rbc[missing]}"
rbc_to_array _n "${rbc[new]}"
rbc_to_array _d "${rbc[different]}"
rbc_to_array _b "${rbc[behind]}"
rbc_to_array _a "${rbc[ahead]}"
rbc_to_array _v "${rbc[diverged]}"
rbc_to_array _s "${rbc[same]}"

assert_eq 1 "${#_m[@]}" 'one missing' \
	&& assert_eq 'only_src' "${_m[0]}" \
	&& assert_eq 1 "${#_n[@]}" 'one new' \
	&& assert_eq 'only_tgt' "${_n[0]}" \
	&& assert_eq 1 "${#_d[@]}" 'one different' \
	&& assert_eq 'diff' "${_d[0]}" \
	&& assert_eq 1 "${#_s[@]}" 'one same' \
	&& assert_eq 0 "${#_b[@]}" 'no behind' \
	&& assert_eq 0 "${#_a[@]}" 'no ahead' \
	&& assert_eq 0 "${#_v[@]}" 'no diverged' \
	&& end_test_ok

# --- With direction mode ---
begin_test 'compute: behind, ahead, diverged (direction mode)'
declare -A src2=([feat_behind]="$tip" [feat_ahead]="$base" [feat_diverged]="$tip")
declare -A tgt2=([feat_behind]="$base" [feat_ahead]="$tip" [feat_diverged]="$side_tip")
local -a inc2=('' '' '') exc2=('' '' '') re2=(0 0 0)
declare -A rbc2=() bc2=() ac2=()

compute_ref_categories src2 tgt2 'full' inc2 exc2 re2 rbc2 bc2 ac2

rbc_to_array _b "${rbc2[behind]}"
rbc_to_array _a "${rbc2[ahead]}"
rbc_to_array _v "${rbc2[diverged]}"
rbc_to_array _d "${rbc2[different]}"

assert_eq 1 "${#_b[@]}" 'one behind' \
	&& assert_eq 'feat_behind' "${_b[0]}" \
	&& assert_eq 1 "${#_a[@]}" 'one ahead' \
	&& assert_eq 'feat_ahead' "${_a[0]}" \
	&& assert_eq 1 "${#_v[@]}" 'one diverged' \
	&& assert_eq 'feat_diverged' "${_v[0]}" \
	&& assert_eq 0 "${#_d[@]}" 'no different in direction mode' \
	&& assert_eq 1 "${bc2[feat_behind]}" 'behind count = 1' \
	&& assert_eq 0 "${ac2[feat_behind]}" 'behind ahead count = 0' \
	&& assert_eq 0 "${bc2[feat_ahead]}" 'ahead behind count = 0' \
	&& assert_eq 1 "${ac2[feat_ahead]}" 'ahead count = 1' \
	&& [[ -n "${bc2[feat_diverged]}" ]] \
	&& [[ -n "${ac2[feat_diverged]}" ]] \
	&& end_test_ok

# --- Include filter ---
begin_test 'compute: include filter limits refs'
declare -A src3=([keep]="$base" [drop]="$base")
declare -A tgt3=([keep]="$tip" [drop]="$tip")
local -a inc3=('' '' 'keep') exc3=('' '' '') re3=(0 0 0)
declare -A rbc3=() bc3=() ac3=()

compute_ref_categories src3 tgt3 'none' inc3 exc3 re3 rbc3 bc3 ac3

rbc_to_array _d "${rbc3[different]}"

assert_eq 1 "${#_d[@]}" 'only keep matches' \
	&& assert_eq 'keep' "${_d[0]}" \
	&& end_test_ok

# --- Exclude filter ---
begin_test 'compute: exclude filter removes refs'
declare -A src4=([keep]="$base" [drop]="$base")
declare -A tgt4=([keep]="$tip" [drop]="$tip")
local -a inc4=('' '' '') exc4=('' '' 'drop') re4=(0 0 0)
declare -A rbc4=() bc4=() ac4=()

compute_ref_categories src4 tgt4 'none' inc4 exc4 re4 rbc4 bc4 ac4

rbc_to_array _d "${rbc4[different]}"

assert_eq 1 "${#_d[@]}" 'drop excluded' \
	&& assert_eq 'keep' "${_d[0]}" \
	&& end_test_ok

# --- Exclude wins over include ---
begin_test 'compute: exclude wins when ref matches both'
declare -A src5=([both]="$base")
declare -A tgt5=([both]="$tip")
local -a inc5=('' '' 'both') exc5=('' '' 'both') re5=(0 0 0)
declare -A rbc5=() bc5=() ac5=()

compute_ref_categories src5 tgt5 'none' inc5 exc5 re5 rbc5 bc5 ac5

rbc_to_array _d "${rbc5[different]}"

assert_eq 0 "${#_d[@]}" 'excluded ref dropped' && end_test_ok

# --- ahead-only direction mode ---
begin_test 'compute: ahead-only mode detects ahead, rest to different'
declare -A src6=([feat_behind]="$tip" [feat_ahead]="$base" [feat_diverged]="$tip")
declare -A tgt6=([feat_behind]="$base" [feat_ahead]="$tip" [feat_diverged]="$side_tip")
local -a inc6=('' '' '') exc6=('' '' '') re6=(0 0 0)
declare -A rbc6=() bc6=() ac6=()

compute_ref_categories src6 tgt6 'ahead-only' inc6 exc6 re6 rbc6 bc6 ac6

rbc_to_array _a "${rbc6[ahead]}"
rbc_to_array _b "${rbc6[behind]}"
rbc_to_array _v "${rbc6[diverged]}"
rbc_to_array _d "${rbc6[different]}"

assert_eq 1 "${#_a[@]}" 'one ahead' \
	&& assert_eq 'feat_ahead' "${_a[0]}" \
	&& assert_eq 0 "${#_b[@]}" 'no behind in ahead-only' \
	&& assert_eq 0 "${#_v[@]}" 'no diverged in ahead-only' \
	&& assert_eq 2 "${#_d[@]}" 'two different (behind+diverged fall back)' \
	&& end_test_ok

# --- behind-only direction mode ---
begin_test 'compute: behind-only mode detects behind, rest to different'
declare -A src7=([feat_behind]="$tip" [feat_ahead]="$base" [feat_diverged]="$tip")
declare -A tgt7=([feat_behind]="$base" [feat_ahead]="$tip" [feat_diverged]="$side_tip")
local -a inc7=('' '' '') exc7=('' '' '') re7=(0 0 0)
declare -A rbc7=() bc7=() ac7=()

compute_ref_categories src7 tgt7 'behind-only' inc7 exc7 re7 rbc7 bc7 ac7

rbc_to_array _b "${rbc7[behind]}"
rbc_to_array _a "${rbc7[ahead]}"
rbc_to_array _v "${rbc7[diverged]}"
rbc_to_array _d "${rbc7[different]}"

assert_eq 1 "${#_b[@]}" 'one behind' \
	&& assert_eq 'feat_behind' "${_b[0]}" \
	&& assert_eq 0 "${#_a[@]}" 'no ahead in behind-only' \
	&& assert_eq 0 "${#_v[@]}" 'no diverged in behind-only' \
	&& assert_eq 2 "${#_d[@]}" 'two different (ahead+diverged fall back)' \
	&& end_test_ok

# --- unrelated histories in full mode ---
# Build a second repo with no shared root and fetch its tip into the
# work repo so both commits are reachable without sharing any ancestor.
other_dir="${TEST_TMPDIR}/other_for_compute"
git init -b main "$other_dir" >/dev/null 2>&1
git -C "$other_dir" commit --allow-empty -m 'O1' >/dev/null 2>&1
hash_o=$(git -C "$other_dir" rev-parse HEAD)
git -C "$work" fetch "$other_dir" "$hash_o:refs/git-sync-test/cmp_unrelated" >/dev/null 2>&1

begin_test 'compute: unrelated histories routed to unrelated bucket'
declare -A src8=([feat]="$tip")
declare -A tgt8=([feat]="$hash_o")
local -a inc8=('' '' '') exc8=('' '' '') re8=(0 0 0)
declare -A rbc8=() bc8=() ac8=()

compute_ref_categories src8 tgt8 'full' inc8 exc8 re8 rbc8 bc8 ac8

local -a _u=()
rbc_to_array _u "${rbc8[unrelated]}"
rbc_to_array _v "${rbc8[diverged]}"
rbc_to_array _d "${rbc8[different]}"

assert_eq 1 "${#_u[@]}" 'one unrelated' \
	&& assert_eq 'feat' "${_u[0]}" \
	&& assert_eq 0 "${#_v[@]}" 'not diverged' \
	&& assert_eq 0 "${#_d[@]}" 'not different' \
	&& assert_eq '' "${bc8[feat]:-}" 'no behind count for unrelated' \
	&& assert_eq '' "${ac8[feat]:-}" 'no ahead count for unrelated' \
	&& end_test_ok

# --- unknown bucket: shallow clone, two truncated tips ---
shallow_bare="${TEST_TMPDIR}/shallow_bare.git"
shallow_deep="${TEST_TMPDIR}/shallow_deep_work"
shallow_clone="${TEST_TMPDIR}/shallow_clone"

git init --bare "$shallow_bare" >/dev/null 2>&1
create_work_repo "$shallow_deep"
make_commit "$shallow_deep" 'A1' >/dev/null
hash_a2=$(make_commit "$shallow_deep" 'A2')
for _i in 3 4 5 6 7 8 9 10; do
	make_commit "$shallow_deep" "A${_i}" >/dev/null
done
git -C "$shallow_deep" checkout -b side "$hash_a2" >/dev/null 2>&1
make_commit "$shallow_deep" 'B1' >/dev/null
make_commit "$shallow_deep" 'B2' >/dev/null
make_commit "$shallow_deep" 'B3' >/dev/null
make_commit "$shallow_deep" 'B4' >/dev/null
make_commit "$shallow_deep" 'B5' >/dev/null
git -C "$shallow_deep" push "$shallow_bare" 'main:refs/heads/main' >/dev/null 2>&1
git -C "$shallow_deep" push "$shallow_bare" 'side:refs/heads/side' >/dev/null 2>&1

git clone --depth=2 --branch=main "$shallow_bare" "$shallow_clone" >/dev/null 2>&1
git -C "$shallow_clone" fetch --depth=2 origin 'refs/heads/side:refs/git-sync-test/side' >/dev/null 2>&1

shallow_main_hash=$(git -C "$shallow_clone" rev-parse refs/remotes/origin/main)
shallow_side_hash=$(git -C "$shallow_clone" rev-parse refs/git-sync-test/side)

pushd "$shallow_clone" >/dev/null
begin_test 'compute: shallow tips with unreachable merge-base routed to unknown'
declare -A src9=([feat]="$shallow_main_hash")
declare -A tgt9=([feat]="$shallow_side_hash")
local -a inc9=('' '' '') exc9=('' '' '') re9=(0 0 0)
declare -A rbc9=() bc9=() ac9=()

compute_ref_categories src9 tgt9 'full' inc9 exc9 re9 rbc9 bc9 ac9

local -a _uk=()
rbc_to_array _uk "${rbc9[unknown]}"
rbc_to_array _ur "${rbc9[unrelated]}"
rbc_to_array _vv "${rbc9[diverged]}"

assert_eq 1 "${#_uk[@]}" 'one unknown' \
	&& assert_eq 'feat' "${_uk[0]}" \
	&& assert_eq 0 "${#_ur[@]}" 'not unrelated' \
	&& assert_eq 0 "${#_vv[@]}" 'not diverged' \
	&& assert_eq '' "${bc9[feat]:-}" 'no behind count for unknown' \
	&& assert_eq '' "${ac9[feat]:-}" 'no ahead count for unknown' \
	&& end_test_ok
popd >/dev/null

report_results
}
run_tests
