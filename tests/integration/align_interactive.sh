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

# Build fixture with a locked remote to trigger push failures.
work="${TEST_TMPDIR}/work"
bare_a="${TEST_TMPDIR}/origin.git"
bare_b="${TEST_TMPDIR}/upstream.git"

create_bare_remote "$bare_a"
create_bare_remote "$bare_b"
create_work_repo "$work"
add_and_fetch "$work" origin "$bare_a"
add_and_fetch "$work" upstream "$bare_b"

hash_base=$(make_commit "$work" 'base')

# Create a branch to trigger a push failure
create_branch "$work" fail_br "$hash_base"
push_branch "$work" origin fail_br
git -C "$work" fetch origin --prune >/dev/null 2>&1
git -C "$work" fetch upstream --prune >/dev/null 2>&1

# Lock upstream
lock_bare_repo "$bare_b"

cd "$work"

run_tests() {

# Override TTY check so interactive prompts fire without a real terminal
is_interactive_tty() { return 0; }

# --- Skip choice ---
begin_test 'align interactive: s skips the ref'
local out rc=0
out="$(echo 's' | bash "$SCRIPT_UNDER_TEST" align --on-failure interactive --subset missing origin upstream 2>&1)" || rc=$?
assert_contains "$out" 'skipped' && end_test_ok

# --- Cancel choice ---
begin_test 'align interactive: c cancels'
local out2 rc2=0
out2="$(echo 'c' | bash "$SCRIPT_UNDER_TEST" align --on-failure interactive --subset missing origin upstream 2>&1)" || rc2=$?
assert_contains "$out2" 'failed:' && end_test_ok

# --- EOF on stdin treated as abort ---
begin_test 'align interactive: EOF on stdin aborts'
local out3 rc3=0
out3="$(echo -n '' | bash "$SCRIPT_UNDER_TEST" align --on-failure interactive --subset missing origin upstream 2>&1)" || rc3=$?
assert_contains "$out3" 'failed:' && end_test_ok

# Note: Testing r/p/f/l choices would need a second retry to succeed,
# which requires unlocking the repo between retries. Since our tests run
# with a locked repo, those choices would just fail again. We verify the
# prompt fires and choices are accepted by testing skip/abort.

begin_test 'align interactive: retry then skip'
local out4 rc4=0
# Send "r" (retry, will fail again) then "s" (skip)
out4="$(printf 'r\ns\n' | bash "$SCRIPT_UNDER_TEST" align --on-failure interactive --subset missing origin upstream 2>&1)" || rc4=$?
assert_contains "$out4" 'skipped' && end_test_ok

report_results
}
run_tests
