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

work="${TEST_TMPDIR}/repo"
create_work_repo "$work"
cd "$work"

run_tests() {

# --- load_config_multi ---
begin_test 'load_config_multi: reads multiple values'
git config --add sync.include 'release/*'
git config --add sync.include 'main'
local -a vals=()
load_config_multi sync.include vals
assert_eq 2 "${#vals[@]}" 'two values' \
	&& assert_eq 'release/*' "${vals[0]}" 'first value' \
	&& assert_eq 'main' "${vals[1]}" 'second value' \
	&& end_test_ok

begin_test 'load_config_multi: returns 1 when unset'
local -a empty_vals=()
rc=0
load_config_multi sync.nonexistent empty_vals || rc=$?
assert_status 1 "$rc" \
	&& assert_eq 0 "${#empty_vals[@]}" 'no values' \
	&& end_test_ok

# --- load_config_scalar ---
begin_test 'load_config_scalar: reads single value'
git config sync.align.on-failure abort
local val
val=$(load_config_scalar sync.align.on-failure)
assert_eq 'abort' "$val" && end_test_ok

begin_test 'load_config_scalar: returns 1 when unset'
rc=0
load_config_scalar sync.nonexistent || rc=$?
assert_status 1 "$rc" && end_test_ok

# --- load_config_multi_joined ---
begin_test 'load_config_multi_joined: joins into newline-delimited string'
local -a layers=('' '' '')
load_config_multi_joined sync.include layers 0
local expected
expected=$(printf 'release/*\nmain')
assert_eq "$expected" "${layers[0]}" && end_test_ok

begin_test 'load_config_multi_joined: returns 1 when unset'
local -a layers2=('' '' '')
rc=0
load_config_multi_joined sync.nonexistent layers2 1 || rc=$?
assert_status 1 "$rc" \
	&& assert_eq '' "${layers2[1]}" 'layer unchanged' \
	&& end_test_ok

report_results
}
run_tests
