#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/tests/helpers/env.sh"
source "${SCRIPT_DIR}/tests/helpers/assert.sh"
source "$SCRIPT_UNDER_TEST"

run_tests() {

begin_test 'apply_subset_filters: empty subset keeps all arrays'
declare -A sf=()
local -a a=('x') b=('y') d=('z') bh=('w') ah=('v') dv=('u') id=('t')
apply_subset_filters sf a b d bh ah dv id
assert_eq 1 "${#a[@]}" && assert_eq 1 "${#b[@]}" && assert_eq 1 "${#d[@]}" \
	&& assert_eq 1 "${#bh[@]}" && assert_eq 1 "${#ah[@]}" && assert_eq 1 "${#dv[@]}" \
	&& assert_eq 1 "${#id[@]}" && end_test_ok

begin_test 'apply_subset_filters: subset missing keeps only missing'
declare -A sf2=([missing]=1)
local -a a2=('x') b2=('y') d2=('z') bh2=('w') ah2=('v') dv2=('u') id2=('t')
apply_subset_filters sf2 a2 b2 d2 bh2 ah2 dv2 id2
assert_eq 1 "${#a2[@]}" 'missing kept' \
	&& assert_eq 0 "${#b2[@]}" 'new cleared' \
	&& assert_eq 0 "${#d2[@]}" 'different cleared' \
	&& assert_eq 0 "${#id2[@]}" 'identical cleared' \
	&& end_test_ok

begin_test 'apply_subset_filters: subset same keeps only identical'
declare -A sf3=([same]=1)
local -a a3=('x') b3=('y') d3=('z') bh3=() ah3=() dv3=() id3=('t')
apply_subset_filters sf3 a3 b3 d3 bh3 ah3 dv3 id3
assert_eq 0 "${#a3[@]}" && assert_eq 0 "${#b3[@]}" && assert_eq 0 "${#d3[@]}" \
	&& assert_eq 1 "${#id3[@]}" 'identical kept' && end_test_ok

begin_test 'apply_subset_filters: multiple subsets'
declare -A sf4=([new]=1 [behind]=1)
local -a a4=('x') b4=('y') d4=('z') bh4=('w') ah4=('v') dv4=('u') id4=('t')
apply_subset_filters sf4 a4 b4 d4 bh4 ah4 dv4 id4
assert_eq 0 "${#a4[@]}" && assert_eq 1 "${#b4[@]}" 'new kept' \
	&& assert_eq 0 "${#d4[@]}" && assert_eq 1 "${#bh4[@]}" 'behind kept' \
	&& assert_eq 0 "${#ah4[@]}" && assert_eq 0 "${#dv4[@]}" \
	&& assert_eq 0 "${#id4[@]}" && end_test_ok

report_results
}
run_tests
