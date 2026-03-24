#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/tests/helpers/env.sh"
source "${SCRIPT_DIR}/tests/helpers/assert.sh"
source "$SCRIPT_UNDER_TEST"

run_tests() {

# --- ref_is_included ---
begin_test 'ref_is_included: empty patterns includes everything'
local -a empty=()
ref_is_included 'main' empty
end_test_ok

begin_test 'ref_is_included: matching glob'
local -a pats=('release/*')
ref_is_included 'release/v1' pats
end_test_ok

begin_test 'ref_is_included: non-matching glob'
local -a pats2=('release/*')
rc=0
ref_is_included 'main' pats2 || rc=$?
assert_status 1 "$rc" && end_test_ok

begin_test 'ref_is_included: exact match'
local -a pats3=('main')
ref_is_included 'main' pats3
end_test_ok

begin_test 'ref_is_included: ? glob'
local -a pats4=('v1.?')
ref_is_included 'v1.0' pats4
end_test_ok

# --- ref_is_excluded ---
begin_test 'ref_is_excluded: empty patterns excludes nothing'
local -a empty2=()
rc=0
ref_is_excluded 'main' empty2 || rc=$?
assert_status 1 "$rc" && end_test_ok

begin_test 'ref_is_excluded: matching glob'
local -a xpats=('tmp-*')
ref_is_excluded 'tmp-test' xpats
end_test_ok

begin_test 'ref_is_excluded: non-matching glob'
local -a xpats2=('tmp-*')
rc=0
ref_is_excluded 'main' xpats2 || rc=$?
assert_status 1 "$rc" && end_test_ok

report_results
}
run_tests
