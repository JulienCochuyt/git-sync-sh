#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/tests/helpers/env.sh"
source "${SCRIPT_DIR}/tests/helpers/assert.sh"
source "$SCRIPT_UNDER_TEST"

run_tests() {

begin_test 'apply_subset_filters: empty subset keeps all entries'
declare -A sf=()
declare -A rbc=([missing]='x' [new]='y' [different]='z' [behind]='w' [ahead]='v' [diverged]='u' [same]='t')
apply_subset_filters sf rbc
assert_eq 'x' "${rbc[missing]}" && assert_eq 'y' "${rbc[new]}" && assert_eq 'z' "${rbc[different]}" \
	&& assert_eq 'w' "${rbc[behind]}" && assert_eq 'v' "${rbc[ahead]}" && assert_eq 'u' "${rbc[diverged]}" \
	&& assert_eq 't' "${rbc[same]}" && end_test_ok

begin_test 'apply_subset_filters: subset missing keeps only missing'
declare -A sf2=([missing]=1)
declare -A rbc2=([missing]='x' [new]='y' [different]='z' [behind]='w' [ahead]='v' [diverged]='u' [same]='t')
apply_subset_filters sf2 rbc2
assert_eq 'x' "${rbc2[missing]}" 'missing kept' \
	&& assert_eq '' "${rbc2[new]}" 'new cleared' \
	&& assert_eq '' "${rbc2[different]}" 'different cleared' \
	&& assert_eq '' "${rbc2[same]}" 'same cleared' \
	&& end_test_ok

begin_test 'apply_subset_filters: subset same keeps only same'
declare -A sf3=([same]=1)
declare -A rbc3=([missing]='x' [new]='y' [different]='z' [same]='t')
apply_subset_filters sf3 rbc3
assert_eq '' "${rbc3[missing]}" && assert_eq '' "${rbc3[new]}" && assert_eq '' "${rbc3[different]}" \
	&& assert_eq 't' "${rbc3[same]}" 'same kept' && end_test_ok

begin_test 'apply_subset_filters: multiple subsets'
declare -A sf4=([new]=1 [behind]=1)
declare -A rbc4=([missing]='x' [new]='y' [different]='z' [behind]='w' [ahead]='v' [diverged]='u' [same]='t')
apply_subset_filters sf4 rbc4
assert_eq '' "${rbc4[missing]}" && assert_eq 'y' "${rbc4[new]}" 'new kept' \
	&& assert_eq '' "${rbc4[different]}" && assert_eq 'w' "${rbc4[behind]}" 'behind kept' \
	&& assert_eq '' "${rbc4[ahead]}" && assert_eq '' "${rbc4[diverged]}" \
	&& assert_eq '' "${rbc4[same]}" && end_test_ok

report_results
}
run_tests
