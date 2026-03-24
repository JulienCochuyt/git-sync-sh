#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
# Smoke test: bash -n syntax check.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/tests/helpers/env.sh"
source "${SCRIPT_DIR}/tests/helpers/assert.sh"

begin_test 'bash -n passes'
rc=0
bash -n "$SCRIPT_UNDER_TEST" 2>&1 || rc=$?
assert_status 0 "$rc" 'syntax check should pass' && end_test_ok

report_results
