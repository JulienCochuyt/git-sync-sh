#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/tests/helpers/env.sh"
source "${SCRIPT_DIR}/tests/helpers/assert.sh"
source "$SCRIPT_UNDER_TEST"

run_tests() {

# --- ref_is_accepted: basic behavior ---
begin_test 'ref_is_accepted: no patterns accepts everything'
local -a inc=('' '' '') exc=('' '' '') re=(0 0 0)
ref_is_accepted 'main' inc exc re
end_test_ok

begin_test 'ref_is_accepted: matching include accepts'
local -a inc2=('' '' 'release/*') exc2=('' '' '') re2=(0 0 0)
ref_is_accepted 'release/v1' inc2 exc2 re2
end_test_ok

begin_test 'ref_is_accepted: non-matching include rejects'
local -a inc3=('' '' 'release/*') exc3=('' '' '') re3=(0 0 0)
rc=0
ref_is_accepted 'main' inc3 exc3 re3 || rc=$?
assert_status 1 "$rc" && end_test_ok

begin_test 'ref_is_accepted: exclude rejects matching ref'
local -a inc4=('' '' '') exc4=('' '' 'tmp-*') re4=(0 0 0)
rc=0
ref_is_accepted 'tmp-test' inc4 exc4 re4 || rc=$?
assert_status 1 "$rc" && end_test_ok

begin_test 'ref_is_accepted: exclude does not reject non-matching'
local -a inc5=('' '' '') exc5=('' '' 'tmp-*') re5=(0 0 0)
ref_is_accepted 'main' inc5 exc5 re5
end_test_ok

begin_test 'ref_is_accepted: exclude wins over include at same layer'
local -a inc6=('' '' 'both') exc6=('' '' 'both') re6=(0 0 0)
rc=0
ref_is_accepted 'both' inc6 exc6 re6 || rc=$?
assert_status 1 "$rc" && end_test_ok

begin_test 'ref_is_accepted: exact match'
local -a inc7=('' '' 'main') exc7=('' '' '') re7=(0 0 0)
ref_is_accepted 'main' inc7 exc7 re7
end_test_ok

begin_test 'ref_is_accepted: ? glob'
local -a inc8=('' '' 'v1.?') exc8=('' '' '') re8=(0 0 0)
ref_is_accepted 'v1.0' inc8 exc8 re8
end_test_ok

report_results
}
run_tests
