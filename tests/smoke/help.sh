#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
# Smoke tests: help commands and CLI dispatch.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/tests/helpers/env.sh"
source "${SCRIPT_DIR}/tests/helpers/assert.sh"

run_script() { bash "$SCRIPT_UNDER_TEST" "$@" 2>&1; }

# --- no args ---
begin_test 'no args prints usage and exits non-zero'
rc=0; out=$(run_script) || rc=$?
assert_status 1 "$rc" && assert_contains "$out" 'Usage' && end_test_ok

# --- help variants ---
begin_test '-h exits zero'
rc=0; out=$(run_script -h) || rc=$?
assert_status 0 "$rc" && assert_contains "$out" 'Commands' && end_test_ok

begin_test '--help exits zero'
rc=0; out=$(run_script --help) || rc=$?
assert_status 0 "$rc" && assert_contains "$out" 'Commands' && end_test_ok

# --- unknown command ---
begin_test 'unknown command exits non-zero'
rc=0; out=$(run_script bogus) || rc=$?
assert_status 1 "$rc" && assert_contains "$out" 'Unknown command' && end_test_ok

# --- status --help ---
begin_test 'status --help exits zero'
rc=0; out=$(run_script status --help) || rc=$?
assert_status 0 "$rc" && assert_contains "$out" '--porcelain' && end_test_ok

# --- align --help ---
begin_test 'align --help exits zero'
rc=0; out=$(run_script align --help) || rc=$?
assert_status 0 "$rc" && assert_contains "$out" '--dry-run' && end_test_ok

report_results
