#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/tests/helpers/env.sh"
source "${SCRIPT_DIR}/tests/helpers/assert.sh"
source "$SCRIPT_UNDER_TEST"

begin_test 'verbose_preview: verbose=0 prints nothing'
out="$(verbose_preview 0 0 git push origin main)"
assert_eq '' "$out" && end_test_ok

begin_test 'verbose_preview: verbose=1 dry_run=0 prints run:'
out="$(verbose_preview 0 1 git push origin main)"
assert_contains "$out" 'run:' && assert_contains "$out" 'git' && end_test_ok

begin_test 'verbose_preview: verbose=1 dry_run=1 prints dry-run:'
out="$(verbose_preview 1 1 git push origin main)"
assert_contains "$out" 'dry-run:' && assert_contains "$out" 'git' && end_test_ok

report_results
