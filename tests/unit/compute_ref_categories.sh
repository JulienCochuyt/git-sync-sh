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

report_results
}
run_tests
