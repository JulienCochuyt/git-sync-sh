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

# --- No direction mode ---
begin_test 'compute: missing, new, different, same (no direction)'
declare -A src=([shared]="$base" [only_src]="$base" [diff]="$base")
declare -A tgt=([shared]="$base" [only_tgt]="$tip" [diff]="$tip")
local -a inc=() exc=()
local -a oia=() oib=() diff_arr=() behind=() ahead=() diverged=() identical=()
declare -A catmap=() bc=() ac=()

compute_ref_categories src tgt 'none' inc exc oia oib diff_arr behind ahead diverged identical catmap bc ac

assert_eq 1 "${#oia[@]}" 'one missing' \
	&& assert_eq 'only_src' "${oia[0]}" \
	&& assert_eq 1 "${#oib[@]}" 'one new' \
	&& assert_eq 'only_tgt' "${oib[0]}" \
	&& assert_eq 1 "${#diff_arr[@]}" 'one different' \
	&& assert_eq 'diff' "${diff_arr[0]}" \
	&& assert_eq 1 "${#identical[@]}" 'one same' \
	&& assert_eq 0 "${#behind[@]}" 'no behind' \
	&& assert_eq 0 "${#ahead[@]}" 'no ahead' \
	&& assert_eq 0 "${#diverged[@]}" 'no diverged' \
	&& end_test_ok

# --- With direction mode ---
begin_test 'compute: behind, ahead, diverged (direction mode)'
declare -A src2=([feat_behind]="$tip" [feat_ahead]="$base" [feat_diverged]="$tip")
declare -A tgt2=([feat_behind]="$base" [feat_ahead]="$tip" [feat_diverged]="$side_tip")
local -a inc2=() exc2=()
local -a oia2=() oib2=() diff2=() behind2=() ahead2=() diverged2=() identical2=()
declare -A catmap2=() bc2=() ac2=()

compute_ref_categories src2 tgt2 'full' inc2 exc2 oia2 oib2 diff2 behind2 ahead2 diverged2 identical2 catmap2 bc2 ac2

assert_eq 1 "${#behind2[@]}" 'one behind' \
	&& assert_eq 'feat_behind' "${behind2[0]}" \
	&& assert_eq 1 "${#ahead2[@]}" 'one ahead' \
	&& assert_eq 'feat_ahead' "${ahead2[0]}" \
	&& assert_eq 1 "${#diverged2[@]}" 'one diverged' \
	&& assert_eq 'feat_diverged' "${diverged2[0]}" \
	&& assert_eq 0 "${#diff2[@]}" 'no different in direction mode' \
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
local -a inc3=('keep') exc3=()
local -a oia3=() oib3=() diff3=() behind3=() ahead3=() diverged3=() identical3=()
declare -A catmap3=() bc3=() ac3=()

compute_ref_categories src3 tgt3 'none' inc3 exc3 oia3 oib3 diff3 behind3 ahead3 diverged3 identical3 catmap3 bc3 ac3

assert_eq 1 "${#diff3[@]}" 'only keep matches' \
	&& assert_eq 'keep' "${diff3[0]}" \
	&& end_test_ok

# --- Exclude filter ---
begin_test 'compute: exclude filter removes refs'
declare -A src4=([keep]="$base" [drop]="$base")
declare -A tgt4=([keep]="$tip" [drop]="$tip")
local -a inc4=() exc4=('drop')
local -a oia4=() oib4=() diff4=() behind4=() ahead4=() diverged4=() identical4=()
declare -A catmap4=() bc4=() ac4=()

compute_ref_categories src4 tgt4 'none' inc4 exc4 oia4 oib4 diff4 behind4 ahead4 diverged4 identical4 catmap4 bc4 ac4

assert_eq 1 "${#diff4[@]}" 'drop excluded' \
	&& assert_eq 'keep' "${diff4[0]}" \
	&& end_test_ok

# --- Exclude wins over include ---
begin_test 'compute: exclude wins when ref matches both'
declare -A src5=([both]="$base")
declare -A tgt5=([both]="$tip")
local -a inc5=('both') exc5=('both')
local -a oia5=() oib5=() diff5=() behind5=() ahead5=() diverged5=() identical5=()
declare -A catmap5=() bc5=() ac5=()

compute_ref_categories src5 tgt5 'none' inc5 exc5 oia5 oib5 diff5 behind5 ahead5 diverged5 identical5 catmap5 bc5 ac5

assert_eq 0 "${#diff5[@]}" 'excluded ref dropped' && end_test_ok

# --- ahead-only direction mode ---
begin_test 'compute: ahead-only mode detects ahead, rest to different'
declare -A src6=([feat_behind]="$tip" [feat_ahead]="$base" [feat_diverged]="$tip")
declare -A tgt6=([feat_behind]="$base" [feat_ahead]="$tip" [feat_diverged]="$side_tip")
local -a inc6=() exc6=()
local -a oia6=() oib6=() diff6=() behind6=() ahead6=() diverged6=() identical6=()
declare -A catmap6=() bc6=() ac6=()

compute_ref_categories src6 tgt6 'ahead-only' inc6 exc6 oia6 oib6 diff6 behind6 ahead6 diverged6 identical6 catmap6 bc6 ac6

assert_eq 1 "${#ahead6[@]}" 'one ahead' \
	&& assert_eq 'feat_ahead' "${ahead6[0]}" \
	&& assert_eq 0 "${#behind6[@]}" 'no behind in ahead-only' \
	&& assert_eq 0 "${#diverged6[@]}" 'no diverged in ahead-only' \
	&& assert_eq 2 "${#diff6[@]}" 'two different (behind+diverged fall back)' \
	&& end_test_ok

# --- behind-only direction mode ---
begin_test 'compute: behind-only mode detects behind, rest to different'
declare -A src7=([feat_behind]="$tip" [feat_ahead]="$base" [feat_diverged]="$tip")
declare -A tgt7=([feat_behind]="$base" [feat_ahead]="$tip" [feat_diverged]="$side_tip")
local -a inc7=() exc7=()
local -a oia7=() oib7=() diff7=() behind7=() ahead7=() diverged7=() identical7=()
declare -A catmap7=() bc7=() ac7=()

compute_ref_categories src7 tgt7 'behind-only' inc7 exc7 oia7 oib7 diff7 behind7 ahead7 diverged7 identical7 catmap7 bc7 ac7

assert_eq 1 "${#behind7[@]}" 'one behind' \
	&& assert_eq 'feat_behind' "${behind7[0]}" \
	&& assert_eq 0 "${#ahead7[@]}" 'no ahead in behind-only' \
	&& assert_eq 0 "${#diverged7[@]}" 'no diverged in behind-only' \
	&& assert_eq 2 "${#diff7[@]}" 'two different (ahead+diverged fall back)' \
	&& end_test_ok

report_results
}
run_tests
