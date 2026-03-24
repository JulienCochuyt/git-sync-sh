#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
# Assertion helpers for the test suite.

fail() {
	local msg="${1:-assertion failed}"
	printf '    ASSERTION FAILED: %s\n' "$msg" >&2
	end_test_fail
	return 1
}

assert_eq() {
	local expected="$1"
	local actual="$2"
	local msg="${3:-expected equal values}"

	if [[ "$expected" != "$actual" ]]; then
		printf '    ASSERTION FAILED: %s\n' "$msg" >&2
		printf '      expected: %s\n' "$expected" >&2
		printf '      actual:   %s\n' "$actual" >&2
		end_test_fail
		return 1
	fi
}

assert_contains() {
	local haystack="$1"
	local needle="$2"
	local msg="${3:-expected output to contain string}"

	if [[ "$haystack" != *"$needle"* ]]; then
		printf '    ASSERTION FAILED: %s\n' "$msg" >&2
		printf '      needle: %s\n' "$needle" >&2
		printf '      haystack:\n%s\n' "$haystack" >&2
		end_test_fail
		return 1
	fi
}

assert_not_contains() {
	local haystack="$1"
	local needle="$2"
	local msg="${3:-expected output to NOT contain string}"

	if [[ "$haystack" == *"$needle"* ]]; then
		printf '    ASSERTION FAILED: %s\n' "$msg" >&2
		printf '      unwanted: %s\n' "$needle" >&2
		printf '      haystack:\n%s\n' "$haystack" >&2
		end_test_fail
		return 1
	fi
}

assert_status() {
	local expected="$1"
	local actual="$2"
	local msg="${3:-unexpected exit status}"

	if ((expected != actual)); then
		printf '    ASSERTION FAILED: %s\n' "$msg" >&2
		printf '      expected exit: %d\n' "$expected" >&2
		printf '      actual exit:   %d\n' "$actual" >&2
		end_test_fail
		return 1
	fi
}

assert_line_count() {
	local expected="$1"
	local text="$2"
	local msg="${3:-unexpected line count}"

	local actual=0
	if [[ -n "$text" ]]; then
		actual="$(printf '%s\n' "$text" | wc -l)"
		actual="${actual// /}"
	fi

	if ((expected != actual)); then
		printf '    ASSERTION FAILED: %s\n' "$msg" >&2
		printf '      expected lines: %d\n' "$expected" >&2
		printf '      actual lines:   %d\n' "$actual" >&2
		printf '      text:\n%s\n' "$text" >&2
		end_test_fail
		return 1
	fi
}
