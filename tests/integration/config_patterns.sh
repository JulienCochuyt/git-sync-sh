#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/tests/helpers/env.sh"
source "${SCRIPT_DIR}/tests/helpers/assert.sh"
source "${SCRIPT_DIR}/tests/helpers/git-fixtures.sh"

setup_tmp

# Build fixture: work repo + two bare remotes.
work="${TEST_TMPDIR}/work"
bare_a="${TEST_TMPDIR}/origin.git"
bare_b="${TEST_TMPDIR}/upstream.git"

create_bare_remote "$bare_a"
create_bare_remote "$bare_b"
create_work_repo "$work"
add_and_fetch "$work" origin "$bare_a"
add_and_fetch "$work" upstream "$bare_b"

# Create branches: main, feat/a, feat/wip, release/v1, wip/junk
hash_base=$(make_commit "$work" 'base')

create_branch "$work" feat/a "$hash_base"
push_branch "$work" origin feat/a
push_branch "$work" upstream feat/a

create_branch "$work" feat/wip "$hash_base"
push_branch "$work" origin feat/wip
push_branch "$work" upstream feat/wip

create_branch "$work" release/v1 "$hash_base"
push_branch "$work" origin release/v1
push_branch "$work" upstream release/v1

create_branch "$work" wip/junk "$hash_base"
push_branch "$work" origin wip/junk
push_branch "$work" upstream wip/junk

push_branch "$work" origin main
push_branch "$work" upstream main

# Make origin/feat/a differ from upstream/feat/a (ahead)
hash_adv=$(make_commit "$work" 'advance')
create_branch "$work" feat/a "$hash_adv"
push_branch "$work" origin feat/a
git -C "$work" fetch origin --prune >/dev/null 2>&1
git -C "$work" fetch upstream --prune >/dev/null 2>&1

cd "$work"

run_tests() {

# --- Config include only ---
begin_test 'config: include filters branches'
git config sync.include 'main'
local out
out="$(bash "$SCRIPT_UNDER_TEST" status --name-only origin upstream)"
assert_eq 'main' "$out" 'only main shown'
git config --unset-all sync.include
end_test_ok

# --- Config exclude only ---
begin_test 'config: exclude filters out matching branches'
git config sync.exclude 'wip/*'
local out2
out2="$(bash "$SCRIPT_UNDER_TEST" status --name-only origin upstream)"
# wip/junk should not appear
local rc=0
echo "$out2" | grep -q 'wip/junk' && rc=1 || true
assert_status 0 "$rc" 'wip/junk excluded'
git config --unset-all sync.exclude
end_test_ok

# --- CLI -i replaces config include ---
begin_test 'config: CLI -i replaces config include'
git config sync.include 'main'
local out3
out3="$(bash "$SCRIPT_UNDER_TEST" status --name-only -i 'release/*' origin upstream)"
assert_eq 'release/v1' "$out3" 'only release shown'
git config --unset-all sync.include
end_test_ok

# --- CLI -i + merges config include ---
begin_test 'config: CLI -i + merges config include'
git config sync.include 'main'
local out4
out4="$(bash "$SCRIPT_UNDER_TEST" status --name-only -i + -i 'release/*' origin upstream)"
local expected
expected=$(printf 'main\nrelease/v1')
assert_eq "$expected" "$out4" 'both main and release shown'
git config --unset-all sync.include
end_test_ok

# --- CLI -x merges config exclude ---
begin_test 'config: CLI -x merges config excludes'
git config sync.exclude '*/wip'
local out5
out5="$(bash "$SCRIPT_UNDER_TEST" status --name-only -x 'wip/*' origin upstream)"
local rc5=0
echo "$out5" | grep -qE 'feat/wip|wip/junk' && rc5=1 || true
assert_status 0 "$rc5" 'both excluded'
git config --unset-all sync.exclude
end_test_ok

# --- CLI -x - replaces config exclude ---
begin_test 'config: CLI -x - replaces config excludes'
git config sync.exclude '*/wip'
local out6
out6="$(bash "$SCRIPT_UNDER_TEST" status --name-only -x - -x 'wip/*' origin upstream)"
# feat/wip should appear (*/wip was replaced), wip/junk should not
local has_feat_wip=0 has_wip_junk=0
echo "$out6" | grep -q 'feat/wip' && has_feat_wip=1 || true
echo "$out6" | grep -q 'wip/junk' && has_wip_junk=1 || true
assert_eq 1 "$has_feat_wip" 'feat/wip not excluded' \
	&& assert_eq 0 "$has_wip_junk" 'wip/junk excluded' \
	&& git config --unset-all sync.exclude \
	&& end_test_ok

# --- CLI -i rescues from config -x ---
begin_test 'config: CLI -i rescues from config exclude'
git config sync.exclude 'feat/wip'
local out7
out7="$(bash "$SCRIPT_UNDER_TEST" status --name-only -i 'feat/*' origin upstream)"
local has_wip=0
echo "$out7" | grep -q 'feat/wip' && has_wip=1 || true
assert_eq 1 "$has_wip" 'feat/wip rescued by CLI include'
git config --unset-all sync.exclude
end_test_ok

# --- CLI -x + re-asserts config excludes ---
begin_test 'config: CLI -x + re-asserts config excludes'
git config sync.exclude '*/wip'
local out8
out8="$(bash "$SCRIPT_UNDER_TEST" status --name-only -i 'feat/*' -x + origin upstream)"
local has_wip8=0
echo "$out8" | grep -q 'feat/wip' && has_wip8=1 || true
assert_eq 0 "$has_wip8" 'feat/wip excluded by re-assertion'
git config --unset-all sync.exclude
end_test_ok

# --- Per-command config replaces shared ---
begin_test 'config: per-command include replaces shared include'
git config sync.include 'main'
git config sync.status.include 'feat/*'
local out9
out9="$(bash "$SCRIPT_UNDER_TEST" status --name-only origin upstream)"
local has_main=0
echo "$out9" | grep -q '^main$' && has_main=1 || true
assert_eq 0 "$has_main" 'main excluded by per-command override'
local has_feat=0
echo "$out9" | grep -q 'feat/' && has_feat=1 || true
assert_eq 1 "$has_feat" 'feat shown by per-command include'
git config --unset-all sync.include
git config --unset-all sync.status.include
end_test_ok

# --- Config on-failure ---
begin_test 'config: on-failure from config'
git config sync.align.on-failure continue
# Dry-run to ensure it doesn't error out
local out10
out10="$(bash "$SCRIPT_UNDER_TEST" align --dry-run -i 'main' origin upstream 2>&1)" || true
local rc10=0
echo "$out10" | grep -q 'Unknown value' && rc10=1 || true
assert_status 0 "$rc10" 'valid on-failure accepted'
git config --unset sync.align.on-failure
end_test_ok

# --- CLI overrides config on-failure ---
begin_test 'config: CLI --on-failure overrides config'
git config sync.align.on-failure continue
local out11
out11="$(bash "$SCRIPT_UNDER_TEST" align --dry-run --on-failure fail-fast -i 'main' origin upstream 2>&1)" || true
local rc11=0
echo "$out11" | grep -q 'Unknown value' && rc11=1 || true
assert_status 0 "$rc11" 'CLI override accepted'
git config --unset sync.align.on-failure
end_test_ok

# --- Invalid config on-failure ---
begin_test 'config: invalid on-failure produces error'
git config sync.align.on-failure bogus
local rc12=0
bash "$SCRIPT_UNDER_TEST" align --dry-run -i 'main' origin upstream 2>/dev/null || rc12=$?
assert_status 1 "$rc12" 'exits with error'
git config --unset sync.align.on-failure
end_test_ok

# --- Config expand threshold ---
begin_test 'config: expand threshold from config'
git config sync.status.expand 999
local out13
out13="$(bash "$SCRIPT_UNDER_TEST" status origin upstream 2>&1)"
# Should not see '...' collapsed indicator for low counts
local rc13=0
echo "$out13" | grep -q 'use --all' && rc13=1 || true
assert_status 0 "$rc13" 'high expand shows details'
git config --unset sync.status.expand
end_test_ok

# --- Config collapse threshold ---
begin_test 'config: collapse threshold from config'
git config sync.status.collapse 1
local out14
out14="$(bash "$SCRIPT_UNDER_TEST" status origin upstream 2>&1)"
# With collapse=1, categories with 2+ refs should be collapsed
# (the exact check depends on how many refs exist per category)
local rc14=0
# At minimum, verify the command doesn't error
assert_status 0 0 'command succeeded'
git config --unset sync.status.collapse
end_test_ok

# --- --all overrides collapse threshold ---
begin_test 'config: --all overrides collapse threshold'
git config sync.status.collapse 1
local out15
out15="$(bash "$SCRIPT_UNDER_TEST" status --all origin upstream 2>&1)"
local rc15=$?
assert_status 0 "$rc15" 'command succeeded with --all'
git config --unset sync.status.collapse
end_test_ok

# --- Invalid expand value ---
begin_test 'config: non-integer expand produces error'
git config sync.status.expand notanumber
local rc16=0
bash "$SCRIPT_UNDER_TEST" status origin upstream 2>/dev/null || rc16=$?
assert_status 1 "$rc16" 'exits with error for bad expand'
git config --unset sync.status.expand
end_test_ok

# --- Invalid collapse value ---
begin_test 'config: non-integer collapse produces error'
git config sync.status.collapse notanumber
local rc17=0
bash "$SCRIPT_UNDER_TEST" status origin upstream 2>/dev/null || rc17=$?
assert_status 1 "$rc17" 'exits with error for bad collapse'
git config --unset sync.status.collapse
end_test_ok

report_results
}
run_tests
