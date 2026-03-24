#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
# Test runner — discovers and executes test files, reports results.

set -euo pipefail

RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER="${1:-}"

total_files=0
passed_files=0
failed_files=0
failed_names=()

# Collect test files in stable order.
test_files=()
for dir in smoke unit integration; do
	if [[ -d "${RUNNER_DIR}/${dir}" ]]; then
		while IFS= read -r -d '' f; do
			test_files+=("$f")
		done < <(find "${RUNNER_DIR}/${dir}" -name '*.sh' -print0 | LC_ALL=C sort -z)
	fi
done

for test_file in "${test_files[@]}"; do
	base="$(basename "$test_file")"

	# Apply filter if specified.
	if [[ -n "$FILTER" && "$base" != *"$FILTER"* ]]; then
		continue
	fi

	((total_files += 1))
	rel="${test_file#"${RUNNER_DIR}/"}"
	printf '[%s]\n' "$rel"

	if bash "$test_file"; then
		((passed_files += 1))
	else
		((failed_files += 1))
		failed_names+=("$rel")
	fi
done

printf '\n========================================\n'
printf 'Files: %d total, %d passed, %d failed\n' "$total_files" "$passed_files" "$failed_files"

if ((failed_files > 0)); then
	printf '\nFailed:\n'
	for name in "${failed_names[@]}"; do
		printf '  %s\n' "$name"
	done
	exit 1
fi

printf 'All tests passed.\n'
