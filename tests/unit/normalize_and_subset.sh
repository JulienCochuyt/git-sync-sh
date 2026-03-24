#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/tests/helpers/env.sh"
source "${SCRIPT_DIR}/tests/helpers/assert.sh"
source "$SCRIPT_UNDER_TEST"

run_tests() {

# --- normalize_subset_category ---
begin_test 'normalize: valid categories returned as-is'
for cat in new missing different same behind ahead diverged; do
	out="$(normalize_subset_category "$cat")"
	assert_eq "$cat" "$out" "category $cat"
done
end_test_ok

begin_test 'normalize: case insensitive'
assert_eq 'new' "$(normalize_subset_category 'New')" \
	&& assert_eq 'behind' "$(normalize_subset_category 'BEHIND')" \
	&& assert_eq 'diverged' "$(normalize_subset_category 'Diverged')" \
	&& end_test_ok

begin_test 'normalize: unknown category fails'
local rc=0
normalize_subset_category 'bogus' >/dev/null 2>&1 || rc=$?
assert_status 1 "$rc" && end_test_ok

# --- add_subset_categories_or_exit ---
begin_test 'add_subset: single category (plain)'
declare -A sp=() sa=() sr=()
add_subset_categories_or_exit 'new' sp sa sr hint_status
assert_eq '1' "${sp[new]}" && end_test_ok

begin_test 'add_subset: comma-separated categories (plain)'
declare -A sp2=() sa2=() sr2=()
add_subset_categories_or_exit 'new,missing,same' sp2 sa2 sr2 hint_status
assert_eq '1' "${sp2[new]}" && assert_eq '1' "${sp2[missing]}" && assert_eq '1' "${sp2[same]}" && end_test_ok

begin_test 'add_subset: spaces around categories trimmed'
declare -A sp3=() sa3=() sr3=()
add_subset_categories_or_exit ' behind , ahead ' sp3 sa3 sr3 hint_status
assert_eq '1' "${sp3[behind]}" && assert_eq '1' "${sp3[ahead]}" && end_test_ok

begin_test 'add_subset: empty entry rejected'
local rc2=0
(declare -A sp4=() sa4=() sr4=(); add_subset_categories_or_exit 'new,,missing' sp4 sa4 sr4 hint_status) &>/dev/null || rc2=$?
assert_status 1 "$rc2" && end_test_ok

begin_test 'add_subset: unknown category rejected'
local rc3=0
(declare -A sp5=() sa5=() sr5=(); add_subset_categories_or_exit 'new,bogus' sp5 sa5 sr5 hint_status) &>/dev/null || rc3=$?
assert_status 1 "$rc3" && end_test_ok

# --- +/- prefix parsing ---
begin_test 'add_subset: + prefix routed to add map'
declare -A sp6=() sa6=() sr6=()
add_subset_categories_or_exit '+same' sp6 sa6 sr6 hint_status
assert_eq '' "${sp6[same]+x}" \
	&& assert_eq '1' "${sa6[same]}" \
	&& assert_eq '' "${sr6[same]+x}" \
	&& end_test_ok

begin_test 'add_subset: - prefix routed to remove map'
declare -A sp7=() sa7=() sr7=()
add_subset_categories_or_exit '-new' sp7 sa7 sr7 hint_status
assert_eq '' "${sp7[new]+x}" \
	&& assert_eq '' "${sa7[new]+x}" \
	&& assert_eq '1' "${sr7[new]}" \
	&& end_test_ok

begin_test 'add_subset: mixed plain, +, and - entries'
declare -A sp8=() sa8=() sr8=()
add_subset_categories_or_exit 'missing,+same,-new' sp8 sa8 sr8 hint_status
assert_eq '1' "${sp8[missing]}" \
	&& assert_eq '1' "${sa8[same]}" \
	&& assert_eq '1' "${sr8[new]}" \
	&& end_test_ok

begin_test 'add_subset: empty category after prefix rejected'
local rc4=0
(declare -A sp9=() sa9=() sr9=(); add_subset_categories_or_exit '+' sp9 sa9 sr9 hint_status) &>/dev/null || rc4=$?
assert_status 1 "$rc4" && end_test_ok

# --- resolve_subset_filters ---
begin_test 'resolve: plain entries replace defaults'
declare -A rp=([missing]=1) ra=() rr=() rd=([missing]=1 [new]=1 [different]=1) ro=()
resolve_subset_filters rp ra rr rd ro
assert_eq '1' "${ro[missing]}" \
	&& assert_eq '' "${ro[new]+x}" \
	&& assert_eq '' "${ro[different]+x}" \
	&& end_test_ok

begin_test 'resolve: + entries add to defaults'
declare -A rp2=() ra2=([same]=1) rr2=() rd2=([missing]=1 [new]=1 [different]=1) ro2=()
resolve_subset_filters rp2 ra2 rr2 rd2 ro2
assert_eq '1' "${ro2[missing]}" \
	&& assert_eq '1' "${ro2[new]}" \
	&& assert_eq '1' "${ro2[different]}" \
	&& assert_eq '1' "${ro2[same]}" \
	&& end_test_ok

begin_test 'resolve: - entries remove from defaults'
declare -A rp3=() ra3=() rr3=([new]=1) rd3=([missing]=1 [new]=1 [different]=1) ro3=()
resolve_subset_filters rp3 ra3 rr3 rd3 ro3
assert_eq '1' "${ro3[missing]}" \
	&& assert_eq '' "${ro3[new]+x}" \
	&& assert_eq '1' "${ro3[different]}" \
	&& end_test_ok

begin_test 'resolve: plain + add combined'
declare -A rp4=([missing]=1) ra4=([same]=1) rr4=() rd4=([missing]=1 [new]=1 [different]=1) ro4=()
resolve_subset_filters rp4 ra4 rr4 rd4 ro4
assert_eq '1' "${ro4[missing]}" \
	&& assert_eq '1' "${ro4[same]}" \
	&& assert_eq '' "${ro4[new]+x}" \
	&& assert_eq '' "${ro4[different]+x}" \
	&& end_test_ok

begin_test 'resolve: empty inputs use defaults'
declare -A rp5=() ra5=() rr5=() rd5=([missing]=1 [different]=1) ro5=()
resolve_subset_filters rp5 ra5 rr5 rd5 ro5
assert_eq '1' "${ro5[missing]}" \
	&& assert_eq '1' "${ro5[different]}" \
	&& end_test_ok

report_results
}
run_tests
