#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/tests/helpers/env.sh"
source "${SCRIPT_DIR}/tests/helpers/assert.sh"
source "$SCRIPT_UNDER_TEST"

# Helper: run resolve_patterns + ref_is_accepted against a ref set.
# Returns accepted refs as a sorted, space-separated string.
resolve_and_accept() {
	local -n _test_inc="$1"
	local -n _test_exc="$2"
	local -n _test_re="$3"
	shift 3
	local -a refs=("$@")

	resolve_patterns _test_inc _test_exc _test_re

	local -a accepted=()
	local ref
	for ref in "${refs[@]}"; do
		if ref_is_accepted "$ref" _test_inc _test_exc _test_re; then
			accepted+=("$ref")
		fi
	done
	if ((${#accepted[@]} == 0)); then
		echo ''
		return
	fi
	mapfile -t accepted < <(printf '%s\n' "${accepted[@]}" | LC_ALL=C sort)
	echo "${accepted[*]}"
}

run_tests() {

local -a ALL_REFS=(feat/a feat/wip hotfix/1 main release/a release/wip)

# --- No patterns anywhere → all refs ---
begin_test 'resolve: no patterns anywhere accepts all refs'
local -a i0=('' '' '') x0=('' '' '') r0=(0 0 0)
local result
result=$(resolve_and_accept i0 x0 r0 "${ALL_REFS[@]}")
assert_eq 'feat/a feat/wip hotfix/1 main release/a release/wip' "$result" && end_test_ok

# --- L0 include only ---
begin_test 'resolve: L0 include only'
local -a i1=('main' '' '') x1=('' '' '') r1=(0 0 0)
result=$(resolve_and_accept i1 x1 r1 "${ALL_REFS[@]}")
assert_eq 'main' "$result" && end_test_ok

# --- L0 exclude only ---
begin_test 'resolve: L0 exclude only'
local -a i2=('' '' '') x2=('*/wip' '' '') r2=(0 0 0)
result=$(resolve_and_accept i2 x2 r2 "${ALL_REFS[@]}")
assert_eq 'feat/a hotfix/1 main release/a' "$result" && end_test_ok

# --- L2 bare -i replaces L0 ---
begin_test 'resolve: L2 bare -i replaces L0 includes'
local -a i3=('main' '' 'feat/*') x3=('' '' '') r3=(0 0 0)
result=$(resolve_and_accept i3 x3 r3 "${ALL_REFS[@]}")
assert_eq 'feat/a feat/wip' "$result" && end_test_ok

# --- L2 -i + merges with L0 ---
begin_test 'resolve: L2 -i + merges with L0'
local -a i4=('main' '' $'+\nfeat/*') x4=('' '' '') r4=(0 0 0)
result=$(resolve_and_accept i4 x4 r4 "${ALL_REFS[@]}")
assert_eq 'feat/a feat/wip main' "$result" && end_test_ok

# --- L2 bare -x merges with L0 ---
begin_test 'resolve: L2 bare -x merges with L0 excludes'
local -a i5=('' '' '') x5=('*/wip' '' '*/a') r5=(0 0 0)
result=$(resolve_and_accept i5 x5 r5 "${ALL_REFS[@]}")
assert_eq 'hotfix/1 main' "$result" && end_test_ok

# --- L2 -x - replaces L0 ---
begin_test 'resolve: L2 -x - replaces L0 excludes'
local -a i6=('' '' '') x6=('*/wip' '' $'-\n*/a') r6=(0 0 0)
result=$(resolve_and_accept i6 x6 r6 "${ALL_REFS[@]}")
assert_eq 'feat/wip hotfix/1 main release/wip' "$result" && end_test_ok

# --- L2 -x + re-asserts ---
begin_test 'resolve: L2 -x + re-asserts L0 excludes on includes'
local -a i7=($'main\nfeat/*' '' '') x7=('*/wip' '' '+') r7=(0 0 0)
result=$(resolve_and_accept i7 x7 r7 "${ALL_REFS[@]}")
assert_eq 'feat/a main' "$result" && end_test_ok

# --- L2 -i rescues from L0 -x ---
begin_test 'resolve: L2 -i rescues from L0 exclude'
local -a i8=('' '' 'feat/*') x8=('feat/wip' '' '') r8=(0 0 0)
result=$(resolve_and_accept i8 x8 r8 "${ALL_REFS[@]}")
assert_eq 'feat/a feat/wip' "$result" && end_test_ok

# --- L2 -i + -x + ---
begin_test 'resolve: L2 -i + with -x + re-asserts'
local -a i9=('main' '' $'+\nfeat/*') x9=('*/wip' '' '+') r9=(0 0 0)
result=$(resolve_and_accept i9 x9 r9 "${ALL_REFS[@]}")
assert_eq 'feat/a main' "$result" && end_test_ok

# --- L1 replaces L0 inc ---
begin_test 'resolve: L1 replaces L0 includes'
local -a i10=('main' 'feat/*' '') x10=('' '' '') r10=(0 0 0)
result=$(resolve_and_accept i10 x10 r10 "${ALL_REFS[@]}")
assert_eq 'feat/a feat/wip' "$result" && end_test_ok

# --- L1 + merges L0 inc ---
begin_test 'resolve: L1 + merges L0 includes'
local -a i11=('main' $'+\nfeat/*' '') x11=('' '' '') r11=(0 0 0)
result=$(resolve_and_accept i11 x11 r11 "${ALL_REFS[@]}")
assert_eq 'feat/a feat/wip main' "$result" && end_test_ok

# --- Three layers ---
begin_test 'resolve: three layers with merge + rescue'
local -a i12=('main' $'+\nfeat/*' $'+\nhotfix/*') x12=('*/wip' '' '') r12=(0 0 0)
result=$(resolve_and_accept i12 x12 r12 "${ALL_REFS[@]}")
assert_eq 'feat/a feat/wip hotfix/1 main' "$result" && end_test_ok

report_results
}
run_tests
