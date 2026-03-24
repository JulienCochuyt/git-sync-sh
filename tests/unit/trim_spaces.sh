#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/tests/helpers/env.sh"
source "${SCRIPT_DIR}/tests/helpers/assert.sh"
source "$SCRIPT_UNDER_TEST"

begin_test 'trim_spaces: no spaces'
assert_eq 'hello' "$(trim_spaces 'hello')" && end_test_ok

begin_test 'trim_spaces: leading spaces'
assert_eq 'hello' "$(trim_spaces '   hello')" && end_test_ok

begin_test 'trim_spaces: trailing spaces'
assert_eq 'hello' "$(trim_spaces 'hello   ')" && end_test_ok

begin_test 'trim_spaces: both sides'
assert_eq 'hello' "$(trim_spaces '  hello  ')" && end_test_ok

begin_test 'trim_spaces: tabs and mixed whitespace'
assert_eq 'hello' "$(trim_spaces $'\t hello \t')" && end_test_ok

begin_test 'trim_spaces: inner spaces preserved'
assert_eq 'hello world' "$(trim_spaces '  hello world  ')" && end_test_ok

begin_test 'trim_spaces: empty string'
assert_eq '' "$(trim_spaces '')" && end_test_ok

report_results
