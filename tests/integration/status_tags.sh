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
# Tag tests use @remote mode (git ls-remote) since load_local_tags ignores
# the remote name and loads a single set from refs/tags.
work="${TEST_TMPDIR}/work"
bare_a="${TEST_TMPDIR}/origin.git"
bare_b="${TEST_TMPDIR}/upstream.git"

create_bare_remote "$bare_a"
create_bare_remote "$bare_b"
create_work_repo "$work"
add_and_fetch "$work" origin "$bare_a"
add_and_fetch "$work" upstream "$bare_b"

# shared_tag: same lightweight tag on both
hash_base=$(make_commit "$work" 'base')
create_lightweight_tag "$work" shared_tag "$hash_base"
push_tag "$work" origin shared_tag
push_tag "$work" upstream shared_tag

# only_origin_tag: only in origin
create_lightweight_tag "$work" only_origin_tag "$hash_base"
push_tag "$work" origin only_origin_tag

# only_upstream_tag: only in upstream
create_lightweight_tag "$work" only_upstream_tag "$hash_base"
push_tag "$work" upstream only_upstream_tag

# diff_tag: different commits
create_lightweight_tag "$work" diff_tag "$hash_base"
push_tag "$work" origin diff_tag
hash_other=$(make_commit "$work" 'other')
create_lightweight_tag "$work" diff_tag "$hash_other"
push_tag "$work" upstream diff_tag

# anno_tag: annotated tag (same commit) on both sides
create_annotated_tag "$work" anno_tag "$hash_base" 'annotated'
push_tag "$work" origin anno_tag
push_tag "$work" upstream anno_tag

cd "$work"

run_tests() {

local src="${bare_a}"
local tgt="${bare_b}"

begin_test 'status -t: missing tag (only in source)'
local out
out="$(bash "$SCRIPT_UNDER_TEST" status -t "$src" "$tgt")"
assert_contains "$out" 'Missing: only in' \
	&& assert_contains "$out" 'only_origin_tag' \
	&& end_test_ok

begin_test 'status -t: new tag (only in target)'
local out2
out2="$(bash "$SCRIPT_UNDER_TEST" status -t "$src" "$tgt")"
assert_contains "$out2" 'New: only in' \
	&& assert_contains "$out2" 'only_upstream_tag' \
	&& end_test_ok

begin_test 'status -t: different tag'
local out3
out3="$(bash "$SCRIPT_UNDER_TEST" status -t "$src" "$tgt")"
assert_contains "$out3" 'Different: between' \
	&& assert_contains "$out3" 'diff_tag' \
	&& end_test_ok

begin_test 'status -t: identical tags expanded by default when few'
local out4
out4="$(bash "$SCRIPT_UNDER_TEST" status -t "$src" "$tgt")"
assert_contains "$out4" 'Same: identical in' \
	&& assert_contains "$out4" 'shared_tag' \
	&& assert_contains "$out4" 'anno_tag' \
	&& end_test_ok

begin_test 'status -t --all: identical tags listed'
local out5
out5="$(bash "$SCRIPT_UNDER_TEST" status -t --all "$src" "$tgt")"
assert_contains "$out5" 'Same: identical in' \
	&& assert_contains "$out5" 'shared_tag' \
	&& assert_contains "$out5" 'anno_tag' \
	&& end_test_ok

begin_test 'status -t: annotated tag peeling matches correctly'
# Annotated tags should compare peeled (commit) hashes, so anno_tag should be identical
local out6
out6="$(bash "$SCRIPT_UNDER_TEST" status -t --name-only "$src" "$tgt")"
assert_contains "$out6" 'anno_tag' && end_test_ok

begin_test 'status -t: --subset behind rejected with tags'
local rc=0
bash "$SCRIPT_UNDER_TEST" status -t --subset behind "$src" "$tgt" &>/dev/null || rc=$?
assert_status 1 "$rc" && end_test_ok

begin_test 'status -t: --subset ahead rejected with tags'
local rc_ahead=0
bash "$SCRIPT_UNDER_TEST" status -t --subset ahead "$src" "$tgt" &>/dev/null || rc_ahead=$?
assert_status 1 "$rc_ahead" && end_test_ok

begin_test 'status -t: --subset diverged rejected with tags'
local rc_div=0
bash "$SCRIPT_UNDER_TEST" status -t --subset diverged "$src" "$tgt" &>/dev/null || rc_div=$?
assert_status 1 "$rc_div" && end_test_ok

begin_test 'status -t: empty result'
local out7
out7="$(bash "$SCRIPT_UNDER_TEST" status -t --subset same --exclude '*' "$src" "$tgt")"
assert_contains "$out7" 'No tags to report.' && end_test_ok

begin_test 'status -t: porcelain output'
local out8
out8="$(bash "$SCRIPT_UNDER_TEST" status -t -p "$src" "$tgt")"
assert_contains "$out8" 'missing' \
	&& assert_contains "$out8" 'new' \
	&& assert_contains "$out8" 'different' \
	&& assert_contains "$out8" 'same' \
	&& end_test_ok

begin_test 'status -t: --subset same --name-only shows identical tag names (regression)'
local out9
out9="$(bash "$SCRIPT_UNDER_TEST" status -t --subset same --name-only "$src" "$tgt")"
assert_contains "$out9" 'shared_tag' \
	&& assert_contains "$out9" 'anno_tag' \
	&& assert_not_contains "$out9" 'diff_tag' \
	&& end_test_ok

begin_test 'status -t: plain and @ names are equivalent'
local out_plain
out_plain="$(bash "$SCRIPT_UNDER_TEST" status -t --name-only "$src" "$tgt" 2>/dev/null)"
local out_at
out_at="$(bash "$SCRIPT_UNDER_TEST" status -t --name-only "@${bare_a}" "@${bare_b}" 2>/dev/null)"
assert_eq "$out_plain" "$out_at" && end_test_ok

begin_test 'status -t --all: does not print "No tags to report" when same tags exist'
local out_all
out_all="$(bash "$SCRIPT_UNDER_TEST" status -t --all "$src" "$tgt")"
assert_contains "$out_all" 'Same:' \
	&& assert_not_contains "$out_all" 'No tags to report' \
	&& end_test_ok

report_results
}
run_tests
