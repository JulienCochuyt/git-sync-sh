#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/tests/helpers/env.sh"
source "${SCRIPT_DIR}/tests/helpers/assert.sh"
source "$SCRIPT_UNDER_TEST"

run_tests() {

begin_test 'parse_remote_ref: plain name sets local mode'
local local_name='' local_source=''
parse_remote_ref 'origin' local_name local_source
assert_eq 'origin' "$local_name" && assert_eq 'local' "$local_source" && end_test_ok

begin_test 'parse_remote_ref: @name sets remote mode'
local local_name='' local_source=''
parse_remote_ref '@upstream' local_name local_source
assert_eq 'upstream' "$local_name" && assert_eq 'remote' "$local_source" && end_test_ok

begin_test 'parse_remote_ref: bare @ rejected'
local rc=0
(parse_remote_ref '@' _n _s hint_status) &>/dev/null || rc=$?
assert_status 1 "$rc" 'bare @ should fail' && end_test_ok

report_results
}
run_tests
