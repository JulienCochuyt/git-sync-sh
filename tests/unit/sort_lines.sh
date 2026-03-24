#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/tests/helpers/env.sh"
source "${SCRIPT_DIR}/tests/helpers/assert.sh"
source "$SCRIPT_UNDER_TEST"

begin_test 'sort_lines: empty input returns nothing'
out="$(sort_lines)"
assert_eq '' "$out" && end_test_ok

begin_test 'sort_lines: single element'
out="$(sort_lines 'alpha')"
assert_eq 'alpha' "$out" && end_test_ok

begin_test 'sort_lines: multiple elements sorted'
out="$(sort_lines 'cherry' 'apple' 'banana')"
expected=$'apple\nbanana\ncherry'
assert_eq "$expected" "$out" && end_test_ok

begin_test 'sort_lines: duplicates preserved'
out="$(sort_lines 'a' 'a' 'b')"
expected=$'a\na\nb'
assert_eq "$expected" "$out" && end_test_ok

report_results
