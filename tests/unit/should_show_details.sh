#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/tests/helpers/env.sh"
source "${SCRIPT_DIR}/tests/helpers/assert.sh"
source "$SCRIPT_UNDER_TEST"

run_tests() {

begin_test 'should_show_details: show_all overrides collapsed'
should_show_details 1 100 0 0 1
assert_eq 0 $? && end_test_ok

begin_test 'should_show_details: show_all overrides collapse threshold'
should_show_details 0 200 0 100 1
assert_eq 0 $? && end_test_ok

begin_test 'should_show_details: collapsed, below expand threshold'
should_show_details 1 3 5 0 0
assert_eq 0 $? && end_test_ok

begin_test 'should_show_details: collapsed, at expand threshold'
should_show_details 1 5 5 0 0
assert_eq 0 $? && end_test_ok

begin_test 'should_show_details: collapsed, above expand threshold'
local _rc=0
should_show_details 1 6 5 0 0 || _rc=$?
assert_eq 1 "$_rc" && end_test_ok

begin_test 'should_show_details: collapsed, expand=0 always collapses'
local _rc2=0
should_show_details 1 1 0 0 0 || _rc2=$?
assert_eq 1 "$_rc2" && end_test_ok

begin_test 'should_show_details: expanded, collapse disabled'
should_show_details 0 500 0 0 0
assert_eq 0 $? && end_test_ok

begin_test 'should_show_details: expanded, below collapse threshold'
should_show_details 0 50 0 100 0
assert_eq 0 $? && end_test_ok

begin_test 'should_show_details: expanded, at collapse threshold'
local _rc3=0
should_show_details 0 100 0 100 0 || _rc3=$?
assert_eq 1 "$_rc3" && end_test_ok

begin_test 'should_show_details: expanded, above collapse threshold'
local _rc4=0
should_show_details 0 200 0 100 0 || _rc4=$?
assert_eq 1 "$_rc4" && end_test_ok

begin_test 'should_show_details: both thresholds, expanded large count'
local _rc5=0
should_show_details 0 200 5 100 0 || _rc5=$?
assert_eq 1 "$_rc5" && end_test_ok

begin_test 'should_show_details: both thresholds, collapsed low count'
should_show_details 1 2 5 100 0
assert_eq 0 $? && end_test_ok

begin_test 'should_show_details: expanded, count=0, collapse enabled'
should_show_details 0 0 0 50 0
assert_eq 0 $? && end_test_ok

report_results
}
run_tests
