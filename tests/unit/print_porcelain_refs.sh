#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/tests/helpers/env.sh"
source "${SCRIPT_DIR}/tests/helpers/assert.sh"
source "$SCRIPT_UNDER_TEST"

run_tests() {

begin_test 'print_porcelain_refs: empty string prints nothing'
declare -A src=() tgt=() bc=() ac=()
out="$(print_porcelain_refs 'missing' '' src tgt bc ac)"
assert_eq '' "$out" && end_test_ok

begin_test 'print_porcelain_refs: prints sorted category lines'
local refs_str=$'beta\nalpha'
declare -A src2=([alpha]='aaa' [beta]='bbb')
declare -A tgt2=([alpha]='ccc' [beta]='ddd')
declare -A bc2=([alpha]='3' [beta]='0') ac2=([alpha]='5' [beta]='2')
out="$(print_porcelain_refs 'different' "$refs_str" src2 tgt2 bc2 ac2)"
line1="$(echo "$out" | head -1)"
line2="$(echo "$out" | tail -1)"
assert_contains "$line1" $'different\talpha\taaa\tccc\t3\t5' \
	&& assert_contains "$line2" $'different\tbeta\tbbb\tddd\t0\t2' \
	&& end_test_ok

begin_test 'print_porcelain_refs: missing source uses -'
local refs_str3='only_tgt'
declare -A src3=()
declare -A tgt3=([only_tgt]='eee')
declare -A bc3=() ac3=()
out="$(print_porcelain_refs 'new' "$refs_str3" src3 tgt3 bc3 ac3)"
assert_contains "$out" $'new\tonly_tgt\t-\teee\t-\t-' && end_test_ok

report_results
}
run_tests
