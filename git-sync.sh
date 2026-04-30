#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

readonly GIT_SYNC_VERSION='1.1.0'

readonly COLOR_RED=$'\033[31m'
readonly COLOR_GREEN=$'\033[32m'
readonly COLOR_YELLOW=$'\033[33m'
readonly COLOR_BLUE=$'\033[34m'
readonly COLOR_CYAN=$'\033[36m'
readonly COLOR_RESET=$'\033[0m'

# Section color mapping (human-readable mode)
readonly SECTION_COLOR_MISSING="$COLOR_YELLOW"
readonly SECTION_COLOR_NEW="$COLOR_CYAN"
readonly SECTION_COLOR_DIFFERENT="$COLOR_RED"
readonly SECTION_COLOR_BEHIND="$COLOR_YELLOW"
readonly SECTION_COLOR_AHEAD="$COLOR_BLUE"
readonly SECTION_COLOR_DIVERGED="$COLOR_RED"
readonly SECTION_COLOR_SAME="$COLOR_GREEN"

usage_main() {
	cat <<'EOF'
Usage:
	git sync <command> [<args>]

Commands:
	status   Compare branches or tags across remotes or against the working copy.
	align    Push branches or tags from source to target.

Options:
	-h, --help       Show this help.
	    --version    Print version.

Configuration:
	Defaults can be set via git config. Example:

	    git config sync.include 'release/*'
	    git config --add sync.include 'main'
	    git config sync.exclude 'dependabot/*'
	    git config sync.align.on-failure abort
	    git config sync.status.expand 5
	    git config sync.status.collapse 100

	Patterns are resolved in layers: shared config, per-command config,
	then CLI. For includes, CLI replaces config unless -i + is passed
	to merge. For excludes, CLI merges with config unless -x - is
	passed to replace.

For command-specific help:
	git sync status --help
	git sync align --help
EOF
}

usage_status() {
	cat <<'EOF'
Usage:
	git sync status [<options>]
	git sync status [<options>] @
	git sync status [<options>] [@]<remote>
	git sync status [<options>] <remote> @
	git sync status [<options>] [@]<remote> [@]<remote>

	With no remote, uses the upstream of the current branch, or the
	sole configured remote.
	When one remote is given, compares local branches/tags against it.
	When two remotes are given, compares them against each other.

	By default, reads local tracking refs (refs/remotes/<remote>/*).
	Prefix a remote with @ to query it live via git ls-remote instead.
	For tags (-t), remotes are always queried via ls-remote.

	Bare @ (without a remote name) resolves the default remote and
	compares its local tracking refs against its live state — a quick
	pre-fetch check. With two remotes, bare @ inherits the other
	remote's name. Not supported with --tags.

Options:
	-p, --porcelain   Machine-readable output.
	--name-only       Output only branch/tag names (one per line).
	-t, --tags        Compare tags instead of branches.
	-a, --annotated   With --tags, show only annotated tags.
	-A, --lightweight With --tags, show only lightweight tags.
	-s, --subset <category[,category...]>
	                  Restrict output to selected categories.
	                  Categories: new, missing, different, behind,
	                  ahead, diverged, same.
	                  Prefix with + to add to or - to remove from the
	                  default set (e.g. --subset +same, --subset -new).
	                  Plain entries replace the defaults entirely.

	                  Availability depends on which sides are local:
	                    Both local:      behind, ahead, diverged (not different).
	                    Local + @remote: behind or ahead (depending on which
	                                     side is local) and different.
	                    Both @remote:    different only.
	                    --tags:          different only.
	                  new, missing, and same are always available.

	-i, --include <pattern>
	                  Include branches/tags matching a shell glob pattern.
	                  Replaces config includes. Use -i + to merge with them.
	                  Repeatable.
	-I, --include-from <file>
	                  Include glob patterns listed in <file> (one per line).
	-x, --exclude <pattern>
	                  Exclude branches/tags matching a shell glob pattern.
	                  Merges with config excludes. Use -x - to replace them.
	                  Use -x + to re-assert all excludes after includes.
	                  Repeatable.
	-X, --exclude-from <file>
	                  Exclude glob patterns listed in <file> (one per line).

	-h, --help        Show this help.

Examples:
	git sync status
	git sync status @
	git sync status origin
	git sync status origin @
	git sync status origin upstream
	git sync status -t origin
	git sync status -t origin upstream
	git sync status -i 'release/*' -x 'release/tmp-*' origin upstream
EOF
}

usage_align() {
	cat <<'EOF'
Usage:
	git sync align [<options>] <source> <target>

Options:
	-n, --dry-run       Show actions without pushing.
	-t, --tags          Align tags instead of branches.
	-a, --annotated     With --tags, process only annotated tags.
	-A, --lightweight   With --tags, process only lightweight tags.
	--on-failure <strategy>
	                    Failure strategy: continue, fail-fast, interactive.
	                    Default: interactive.
	-f, --force         Use --force for push attempts.
	-F, --force-with-lease
	                    Use --force-with-lease for push attempts.
	-v, --verbose       Print git commands as they are executed.

	-y, --yes           Skip interactive confirmation before deleting
	                    refs (category new).

	-s, --subset <category[,category...]>
	                    Restrict processing to selected categories.
	                    Prefix with + to add to or - to remove from the
	                    default set (e.g. --subset +new, --subset -missing).
	                    Plain entries replace the defaults entirely.

	                    Common categories:  new, missing.
	                    Branches only:      behind, ahead, diverged.
	                    Tags only:          different.

	-i, --include <pattern>
	                    Include branches/tags matching a shell glob pattern.
	                    Replaces config includes. Use -i + to merge with them.
	                    Repeatable.
	-I, --include-from <file>
	                    Include glob patterns listed in <file> (one per line).
	-x, --exclude <pattern>
	                    Exclude branches/tags matching a shell glob pattern.
	                    Merges with config excludes. Use -x - to replace them.
	                    Use -x + to re-assert all excludes after includes.
	                    Repeatable.
	-X, --exclude-from <file>
	                    Exclude glob patterns listed in <file> (one per line).

	-h, --help          Show this help.

Arguments:
	<source> and <target> are remote names (e.g. origin, upstream).
	For branches, local tracking refs are used for comparison;
	pushes and deletions always target the real remote.
	For tags, remotes are queried live via git ls-remote.

Examples:
	git sync align origin upstream
	git sync align --dry-run --subset missing,behind origin upstream
	git sync align -t origin upstream
	git sync align --on-failure interactive --force-with-lease origin upstream
EOF
}

# Short hint printed on usage errors instead of the full usage text.
usage_hint() {
	printf 'Use "%s --help" for detailed usage.\n' "$1" >&2
}
usage_hint_status() { usage_hint 'status'; }
usage_hint_align()  { usage_hint 'align'; }

sort_lines() {
	if (($# == 0)); then
		return
	fi

	printf '%s\n' "$@" | LC_ALL=C sort
}

# Determine if a category should be shown in detail.
# Args: $1 = normally_collapsed (0 or 1), $2 = count,
#       $3 = expand threshold, $4 = collapse threshold
should_show_details() {
	local normally_collapsed=$1 count=$2 expand=$3 collapse=$4
	if ((normally_collapsed == 1)); then
		((count <= expand))
		return
	fi
	if ((collapse > 0 && count >= collapse)); then
		return 1
	fi
	return 0
}

print_colored_line() {
	local prefix="$1"
	local color="$2"
	local text="$3"

	if [[ -t 1 ]]; then
		printf '%s%b%s%b\n' "$prefix" "$color" "$text" "$COLOR_RESET"
	else
		printf '%s%s\n' "$prefix" "$text"
	fi
}

print_section() {
	local title="$1"
	local color="$2"
	shift 2
	local count=$#

	printf '%s (%d)\n' "$title" "$count"
	if (($# == 0)); then
		print_colored_line '  ' "$color" '(none)'
		return
	fi

	local ref
	for ref in "$@"; do
		print_colored_line '  ' "$color" "$ref"
	done
}

# Format ref names with commit count annotations for directional categories.
# For behind:   "ref  (N commits)"
# For ahead:    "ref  (N commits)"
# For diverged: "ref  (N behind, M ahead)"
format_refs_with_counts() {
	local category="$1"
	local -n frc_behind_map="$2"
	local -n frc_ahead_map="$3"
	shift 3
	local ref b a
	for ref in "$@"; do
		b="${frc_behind_map[$ref]:--}"
		a="${frc_ahead_map[$ref]:--}"
		case "$category" in
			behind)
				if [[ "$b" != '-' ]]; then
					printf '%s  (%s commits)\n' "$ref" "$b"
				else
					printf '%s\n' "$ref"
				fi
				;;
			ahead)
				if [[ "$a" != '-' ]]; then
					printf '%s  (%s commits)\n' "$ref" "$a"
				else
					printf '%s\n' "$ref"
				fi
				;;
			diverged)
				if [[ "$b" != '-' && "$a" != '-' ]]; then
					printf '%s  (%s behind, %s ahead)\n' "$ref" "$b" "$a"
				else
					printf '%s\n' "$ref"
				fi
				;;
		esac
	done
}

# Output: <category>\t<ref>\t<source_hash>\t<target_hash>\t<behind_count>\t<ahead_count>
# Unavailable fields use "-" as sentinel.
print_porcelain_refs() {
	local category="$1"
	local refs_str="$2"
	local -n pr_src_map="$3"
	local -n pr_tgt_map="$4"
	local -n pr_behind_counts="$5"
	local -n pr_ahead_counts="$6"

	[[ -n "$refs_str" ]] || return 0

	local -a pr_refs=()
	mapfile -t pr_refs <<< "$refs_str"
	local -a sorted=()
	local ref
	mapfile -t sorted < <(sort_lines "${pr_refs[@]}")
	for ref in "${sorted[@]}"; do
		printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$category" "$ref" \
			"${pr_src_map[$ref]:--}" "${pr_tgt_map[$ref]:--}" \
			"${pr_behind_counts[$ref]:--}" "${pr_ahead_counts[$ref]:--}"
	done
}



# Classify how target (hash_b) relates to source (hash_a):
#   behind   = target is ancestor of source (fast-forwardable)
#   ahead    = source is ancestor of target
#   diverged = neither is ancestor of the other
# Modes:
#   full         — both sides local; behind/ahead/diverged all reliable.
#   ahead-only   — B is local; only ahead is reliably detectable.
#   behind-only  — A is local; only behind is reliably detectable.
is_interactive_tty() {
	[[ -t 0 ]]
}

classify_direction_relation() {
	local hash_a="$1"
	local hash_b="$2"
	local mode="${3:-full}"

	case "$mode" in
		ahead-only)
			# B is local — "ahead" (A ancestor of B) is always detectable
			# because A's hash must be in B's local ancestry if true.
			if git merge-base --is-ancestor "$hash_a" "$hash_b" >/dev/null 2>&1; then
				printf 'ahead\n'
			else
				printf 'different\n'
			fi
			;;
		behind-only)
			# A is local — "behind" (B ancestor of A) is always detectable
			# because B's hash must be in A's local ancestry if true.
			if git merge-base --is-ancestor "$hash_b" "$hash_a" >/dev/null 2>&1; then
				printf 'behind\n'
			else
				printf 'different\n'
			fi
			;;
		*)
			# full: both sides local — all categories available.
			if git merge-base --is-ancestor "$hash_b" "$hash_a" >/dev/null 2>&1; then
				printf 'behind\n'
			elif git merge-base --is-ancestor "$hash_a" "$hash_b" >/dev/null 2>&1; then
				printf 'ahead\n'
			else
				printf 'diverged\n'
			fi
			;;
	esac
}

load_remote_heads() {
	local remote="$1"
	local -n out_map="$2"

	local hash ref branch
	while IFS=$'\t' read -r hash ref; do
		[[ -z "$hash" || -z "$ref" ]] && continue
		branch="${ref#refs/heads/}"
		[[ "$branch" == "$ref" ]] && continue
		out_map["$branch"]="$hash"
	done < <(git ls-remote "$remote" 'refs/heads/*')
}

load_local_heads() {
	local remote="$1"
	local -n out_map="$2"

	local hash ref branch
	while IFS=$'\t' read -r hash ref; do
		[[ -z "$hash" || -z "$ref" ]] && continue
		branch="${ref#refs/remotes/${remote}/}"
		[[ "$branch" == "$ref" ]] && continue
		[[ "$branch" == "HEAD" ]] && continue
		out_map["$branch"]="$hash"
	done < <(git for-each-ref --format='%(objectname)%09%(refname)' "refs/remotes/${remote}")
}

load_worktree_heads() {
	local -n out_map="$1"

	local hash ref branch
	while IFS=$'\t' read -r hash ref; do
		[[ -z "$hash" || -z "$ref" ]] && continue
		branch="${ref#refs/heads/}"
		[[ "$branch" == "$ref" ]] && continue
		out_map["$branch"]="$hash"
	done < <(git for-each-ref --format='%(objectname)%09%(refname)' refs/heads)
}

# Resolve the default remote for the current branch.
# Tries: 1) upstream remote of current branch, 2) sole configured remote.
# Prints the remote name to stdout. Returns 1 if unable to resolve.
resolve_default_remote() {
	local branch
	branch="$(git symbolic-ref --short HEAD 2>/dev/null)" || true

	if [[ -n "$branch" ]]; then
		local upstream_remote
		upstream_remote="$(git config --get "branch.${branch}.remote" 2>/dev/null)" || true
		if [[ -n "$upstream_remote" ]]; then
			printf '%s\n' "$upstream_remote"
			return 0
		fi
	fi

	local -a remotes
	mapfile -t remotes < <(git remote)
	if ((${#remotes[@]} == 1)); then
		printf '%s\n' "${remotes[0]}"
		return 0
	fi

	return 1
}

# ls-remote lists annotated tags twice: the tag object and the peeled (^{}) commit.
# We prefer the peeled hash so comparisons use the underlying commit.
# $3 = tag_type filter: 0=all, 1=annotated only, 2=lightweight only.
load_remote_tags() {
	local remote="$1"
	local -n out_map="$2"
	local tag_type="${3:-0}"

	local -A _annotated_set=()
	local hash ref tag_name base_name
	while IFS=$'\t' read -r hash ref; do
		[[ -z "$hash" || -z "$ref" ]] && continue

		if [[ "$ref" == refs/tags/*^{} ]]; then
			base_name="${ref#refs/tags/}"
			base_name="${base_name%^\{\}}"
			_annotated_set["$base_name"]=1
			out_map["$base_name"]="$hash"
			continue
		fi

		tag_name="${ref#refs/tags/}"
		[[ "$tag_name" == "$ref" ]] && continue
		if [[ -z "${out_map[$tag_name]+x}" ]]; then
			out_map["$tag_name"]="$hash"
		fi
	done < <(git ls-remote "$remote" 'refs/tags/*')

	# Apply tag type filter.
	if ((tag_type != 0)); then
		for tag_name in "${!out_map[@]}"; do
			if ((tag_type == 1)) && [[ -z "${_annotated_set[$tag_name]+x}" ]]; then
				unset 'out_map[$tag_name]'
			elif ((tag_type == 2)) && [[ -n "${_annotated_set[$tag_name]+x}" ]]; then
				unset 'out_map[$tag_name]'
			fi
		done
	fi
}

# %(*objectname) is the peeled hash for annotated tags, empty for lightweight.
# Uses pipe delimiter (not tab) so empty %(*objectname) produces a real empty
# field — consecutive IFS whitespace characters are folded by bash read.
# $2 = tag_type filter: 0=all, 1=annotated only, 2=lightweight only.
load_local_tags() {
	local -n out_map="$1"
	local tag_type="${2:-0}"

	local object_hash peeled_hash ref tag_name selected_hash
	while IFS='|' read -r object_hash peeled_hash ref; do
		[[ -z "$object_hash" || -z "$ref" ]] && continue
		tag_name="${ref#refs/tags/}"
		[[ "$tag_name" == "$ref" ]] && continue

		# Filter by tag type.
		if ((tag_type == 1)) && [[ -z "$peeled_hash" ]]; then
			continue  # want annotated only, skip lightweight
		fi
		if ((tag_type == 2)) && [[ -n "$peeled_hash" ]]; then
			continue  # want lightweight only, skip annotated
		fi

		selected_hash="$object_hash"
		if [[ -n "$peeled_hash" ]]; then
			selected_hash="$peeled_hash"
		fi

		out_map["$tag_name"]="$selected_hash"
	done < <(git for-each-ref --format='%(objectname)|%(*objectname)|%(refname)' refs/tags)
}

parse_remote_ref() {
	local input_ref="$1"
	local -n out_name="$2"
	local -n out_source="$3"
	local usage_fn="${4:-hint_status}"

	if [[ "$input_ref" == @* ]]; then
		out_source='remote'
		out_name="${input_ref#@}"
	else
		out_source='local'
		out_name="$input_ref"
	fi

	if [[ -z "$out_name" ]]; then
		printf 'Invalid remote ref: %s\n\n' "$input_ref" >&2
		"$usage_fn"
		exit 1
	fi
}

load_pattern_file() {
	local file_path="$1"
	local -n out_patterns="$2"
	local usage_fn="${3:-hint_status}"

	if [[ ! -r "$file_path" ]]; then
		printf 'Cannot read pattern file: %s\n\n' "$file_path" >&2
		"$usage_fn"
		exit 1
	fi

	local line
	# Handle any line ending: LF (Unix), CRLF (Windows), CR (old Mac).
	# tr normalises CR-only and CRLF to plain LF before read processes it.
	while IFS= read -r line || [[ -n "$line" ]]; do
		[[ -z "$line" ]] && continue
		[[ "$line" =~ ^[[:space:]]*# ]] && continue
		out_patterns+=("$line")
	done < <(tr '\r' '\n' < "$file_path" | cat -s)
}

# Load a multi-value git config key into an array.
# Returns 0 if any values found, 1 if key is unset.
load_config_multi() {
	local key="$1"
	local -n _cm_ref="$2"
	local -a _cm_vals=()
	if mapfile -t _cm_vals < <(git config --get-all "$key" 2>/dev/null) \
			&& (("${#_cm_vals[@]}" > 0)) && [[ -n "${_cm_vals[0]}" ]]; then
		_cm_ref+=("${_cm_vals[@]}")
		return 0
	fi
	return 1
}

# Load a single-value git config key.
# Returns 0 if found, 1 if unset. Value printed to stdout.
load_config_scalar() {
	git config --get "$1" 2>/dev/null
}

# Load a multi-value git config key into a newline-delimited string
# at a specific index of an indexed array.
load_config_multi_joined() {
	local key="$1"
	local -n _cmj_ref="$2"
	local idx="$3"
	local -a _cmj_vals=()
	if load_config_multi "$key" _cmj_vals; then
		_cmj_ref[$idx]="$(printf '%s\n' "${_cmj_vals[@]}")"
		return 0
	fi
	return 1
}

# Pass 1: resolve layered include/exclude modifiers in place.
# Takes three indexed array namerefs (each with 3 entries, index = layer):
#   $1 = inc_layers  — newline-delimited include patterns per layer
#   $2 = exc_layers  — newline-delimited exclude patterns per layer
#   $3 = re_exclude  — output: 0 or 1 per layer (re-exclusion flag)
# Strips +/- modifier tokens. Clears earlier layers per merge/replace
# semantics. Sets re_exclude[i]=1 when "+" appears in exc_layers[i].
resolve_patterns() {
	local -n _rp_inc="$1"
	local -n _rp_exc="$2"
	local -n _rp_re="$3"

	local i j
	for i in 0 1 2; do
		# --- Includes ---
		if [[ -n "${_rp_inc[$i]}" ]]; then
			local _has_merge=0
			local _new_inc=''
			local _pat
			while IFS= read -r _pat; do
				[[ -z "$_pat" ]] && continue
				if [[ "$_pat" == '+' ]]; then
					_has_merge=1
				else
					_new_inc+="$_pat"$'\n'
				fi
			done <<< "${_rp_inc[$i]}"
			_new_inc="${_new_inc%$'\n'}"
			if ((!_has_merge)); then
				for ((j = 0; j < i; j++)); do
					_rp_inc[$j]=''
				done
			fi
			_rp_inc[$i]="$_new_inc"
		fi

		# --- Excludes ---
		if [[ -n "${_rp_exc[$i]}" ]]; then
			local _has_replace=0
			local _has_reassert=0
			local _new_exc=''
			local _pat
			while IFS= read -r _pat; do
				[[ -z "$_pat" ]] && continue
				if [[ "$_pat" == '-' ]]; then
					_has_replace=1
				elif [[ "$_pat" == '+' ]]; then
					_has_reassert=1
				else
					_new_exc+="$_pat"$'\n'
				fi
			done <<< "${_rp_exc[$i]}"
			_new_exc="${_new_exc%$'\n'}"
			if ((_has_replace)); then
				for ((j = 0; j < i; j++)); do
					_rp_exc[$j]=''
				done
			fi
			_rp_re[$i]="$_has_reassert"
			_rp_exc[$i]="$_new_exc"
		fi
	done
}

# Pass 2 per-ref: is this ref accepted by the resolved layers?
# Returns 0 (accepted) or 1 (rejected).
ref_is_accepted() {
	local ref="$1"
	local -n _ra_inc="$2"
	local -n _ra_exc="$3"
	local -n _ra_re="$4"

	# has_any_include: true if any layer has non-empty includes
	local has_inc=0
	local i
	for i in 0 1 2; do
		if [[ -n "${_ra_inc[$i]}" ]]; then has_inc=1; break; fi
	done

	local accepted=$((1 - has_inc))   # all refs if no includes, else empty

	for i in 0 1 2; do
		# Step 1: this layer's excludes remove from accepted
		if ((accepted)) && [[ -n "${_ra_exc[$i]}" ]]; then
			local _pat
			while IFS= read -r _pat; do
				[[ -n "$_pat" ]] && [[ "$ref" == $_pat ]] && { accepted=0; break; }
			done <<< "${_ra_exc[$i]}"
		fi

		# Steps 2-3: layer includes (pick from full set, minus own excludes)
		local layer_match=0
		if [[ -n "${_ra_inc[$i]}" ]]; then
			local _pat
			while IFS= read -r _pat; do
				[[ -n "$_pat" ]] && [[ "$ref" == $_pat ]] && { layer_match=1; break; }
			done <<< "${_ra_inc[$i]}"
			if ((layer_match)) && [[ -n "${_ra_exc[$i]}" ]]; then
				while IFS= read -r _pat; do
					[[ -n "$_pat" ]] && [[ "$ref" == $_pat ]] && { layer_match=0; break; }
				done <<< "${_ra_exc[$i]}"
			fi
		fi

		# Step 4: re-exclusion — check all previous layers' excludes
		if ((layer_match && _ra_re[i])); then
			local j
			for ((j = 0; j < i; j++)); do
				[[ -z "${_ra_exc[$j]}" ]] && continue
				while IFS= read -r _pat; do
					[[ -n "$_pat" ]] && [[ "$ref" == $_pat ]] && { layer_match=0; break 2; }
				done <<< "${_ra_exc[$j]}"
			done
		fi

		# Step 5: layer match adds to accepted
		((layer_match)) && accepted=1
	done

	return $((1 - accepted))
}

load_ref_set() {
	local ref_mode="$1"
	local ref="$2"
	local tags_mode="$3"
	local -n target_map="$4"
	local tag_type="${5:-0}"

	if ((tags_mode == 1)); then
		if [[ "$ref_mode" == 'remote' ]]; then
			load_remote_tags "$ref" target_map "$tag_type"
		else
			load_local_tags target_map "$tag_type"
		fi
	else
		if [[ "$ref_mode" == 'remote' ]]; then
			load_remote_heads "$ref" target_map
		elif [[ "$ref_mode" == 'worktree' ]]; then
			load_worktree_heads target_map
		else
			load_local_heads "$ref" target_map
		fi
	fi
}

compute_ref_categories() {
	local -n source_map_ref="$1"
	local -n target_map_ref="$2"
	local direction_mode="$3"
	local -n inc_layers_ref="$4"
	local -n exc_layers_ref="$5"
	local -n re_exclude_ref="$6"
	local -n refs_by_cat_ref="$7"
	local -n behind_count_map_ref="$8"
	local -n ahead_count_map_ref="$9"

	# Initialize all category keys to empty.
	local _cat
	for _cat in missing new different behind ahead diverged same; do
		refs_by_cat_ref[$_cat]=''
	done

	local ref
	for ref in "${!source_map_ref[@]}"; do
		if ! ref_is_accepted "$ref" inc_layers_ref exc_layers_ref re_exclude_ref; then
			continue
		fi

		if [[ -z "${target_map_ref[$ref]+x}" ]]; then
			refs_by_cat_ref[missing]+="$ref"$'\n'
		elif [[ "${source_map_ref[$ref]}" == "${target_map_ref[$ref]}" ]]; then
			refs_by_cat_ref[same]+="$ref"$'\n'
		else
			if [[ "$direction_mode" == 'none' ]]; then
				refs_by_cat_ref[different]+="$ref"$'\n'
			else
				local _dir _left _right
				_dir="$(classify_direction_relation "${source_map_ref[$ref]}" "${target_map_ref[$ref]}" "$direction_mode")"
				case "$_dir" in
					behind|ahead|diverged)
						read -r _left _right < <(git rev-list --count --left-right "${source_map_ref[$ref]}...${target_map_ref[$ref]}" 2>/dev/null) || { _left='-'; _right='-'; }
						behind_count_map_ref["$ref"]="$_left"
						ahead_count_map_ref["$ref"]="$_right"
						;;&
					behind)
						refs_by_cat_ref[behind]+="$ref"$'\n'
						;;
					ahead)
						refs_by_cat_ref[ahead]+="$ref"$'\n'
						;;
					different)
						refs_by_cat_ref[different]+="$ref"$'\n'
						;;
					*)
						refs_by_cat_ref[diverged]+="$ref"$'\n'
						;;
				esac
			fi
		fi
	done

	for ref in "${!target_map_ref[@]}"; do
		if ! ref_is_accepted "$ref" inc_layers_ref exc_layers_ref re_exclude_ref; then
			continue
		fi

		if [[ -z "${source_map_ref[$ref]+x}" ]]; then
			refs_by_cat_ref[new]+="$ref"$'\n'
		fi
	done

	# Strip trailing newlines.
	for _cat in missing new different behind ahead diverged same; do
		refs_by_cat_ref[$_cat]="${refs_by_cat_ref[$_cat]%$'\n'}"
	done
}

apply_subset_filters() {
	local -n subset_filters_ref="$1"
	local -n refs_by_cat_ref="$2"

	if ((${#subset_filters_ref[@]} == 0)); then
		return
	fi

	local _cat
	for _cat in missing new different behind ahead diverged same; do
		[[ -n "${subset_filters_ref[$_cat]+x}" ]] || refs_by_cat_ref[$_cat]=''
	done
}

normalize_subset_category() {
	local lower="${1,,}"
	case "$lower" in
		new|missing|different|same|behind|ahead|diverged)
			printf '%s\n' "$lower"
			;;
		*)
			return 1
			;;
	esac
}

# Strip leading and trailing whitespace using parameter expansion.
trim_spaces() {
	local value="$1"
	value="${value#"${value%%[![:space:]]*}"}"
	value="${value%"${value##*[![:space:]]}"}"
	printf '%s\n' "$value"
}

add_subset_categories_or_exit() {
	local raw_value="$1"
	local -n out_plain="$2"
	local -n out_add="$3"
	local -n out_remove="$4"
	local usage_fn="${5:-hint_status}"

	local -a parts=()
	local part trimmed normalized prefix
	IFS=',' read -r -a parts <<< "$raw_value"

	for part in "${parts[@]}"; do
		trimmed="$(trim_spaces "$part")"
		if [[ -z "$trimmed" ]]; then
			printf 'Option --subset contains an empty category.\n\n' >&2
			"$usage_fn"
			exit 1
		fi

		prefix=''
		if [[ "$trimmed" == +* ]]; then
			prefix='+'
			trimmed="${trimmed:1}"
		elif [[ "$trimmed" == -* ]]; then
			prefix='-'
			trimmed="${trimmed:1}"
		fi

		if [[ -z "$trimmed" ]]; then
			printf 'Option --subset contains an empty category after prefix.\n\n' >&2
			"$usage_fn"
			exit 1
		fi

		if ! normalized="$(normalize_subset_category "$trimmed")"; then
			printf 'Unknown category: %s\n\n' "$trimmed" >&2
			"$usage_fn"
			exit 1
		fi

		case "$prefix" in
			'+') out_add["$normalized"]=1 ;;
			'-') out_remove["$normalized"]=1 ;;
			*)   out_plain["$normalized"]=1 ;;
		esac
	done
}

# Resolve the final subset_filters map from parsed --subset entries.
# 1. If plain entries exist, start from those.
# 2. Otherwise, start from the default set.
# 3. Add + entries.
# 4. Remove - entries.
resolve_subset_filters() {
	local -n rs_plain="$1"
	local -n rs_add="$2"
	local -n rs_remove="$3"
	local -n rs_defaults="$4"
	local -n rs_out="$5"

	# Start from plain entries if any, otherwise from defaults.
	if ((${#rs_plain[@]} > 0)); then
		local cat
		for cat in "${!rs_plain[@]}"; do
			rs_out["$cat"]=1
		done
	else
		local cat
		for cat in "${!rs_defaults[@]}"; do
			rs_out["$cat"]=1
		done
	fi

	# Apply additions.
	local cat
	for cat in "${!rs_add[@]}"; do
		rs_out["$cat"]=1
	done

	# Apply removals.
	local cat
	for cat in "${!rs_remove[@]}"; do
		unset 'rs_out[$cat]'
	done
}

status_print_name_only() {
	local refs_str="$1"
	[[ -n "$refs_str" ]] || return 0

	local -a refs=()
	mapfile -t refs <<< "$refs_str"
	local -a sorted=()
	mapfile -t sorted < <(sort_lines "${refs[@]}")
	printf '%s\n' "${sorted[@]}"
}

status_command() {
	local porcelain=0
	local direction_mode='none'
	local tags_mode=0
	local tag_type=0
	local name_only=0
	local -a included_patterns=()
	local -a excluded_patterns=()
	local -A subset_plain=()
	local -A subset_add=()
	local -A subset_remove=()
	local -A subset_filters=()
	local -a _positional_args=()
	while (($# > 0)); do
		# Expand combined short options (e.g., -ts → -t -s)
		if [[ "$1" =~ ^-[a-zA-Z]{2,}$ ]]; then
			local _combined="$1"
			shift
			local _k
			for ((_k = ${#_combined} - 1; _k >= 1; _k--)); do
				set -- "-${_combined:_k:1}" "$@"
			done
		fi
		case "$1" in
			-p|--porcelain)
				porcelain=1
				shift
				;;
			-t|--tags)
				tags_mode=1
				shift
				;;
			-a|--annotated)
				if ((tag_type == 2)); then
					printf 'Options --annotated and --lightweight are mutually exclusive.\n\n' >&2
					usage_hint_status
					exit 1
				fi
				tag_type=1
				shift
				;;
			-A|--lightweight)
				if ((tag_type == 1)); then
					printf 'Options --annotated and --lightweight are mutually exclusive.\n\n' >&2
					usage_hint_status
					exit 1
				fi
				tag_type=2
				shift
				;;
			--name-only)
				name_only=1
				shift
				;;
			-s|--subset)
				if (($# < 2)); then
					printf 'Option %s requires a value.\n\n' "$1" >&2
					usage_hint_status
					exit 1
				fi
				add_subset_categories_or_exit "$2" subset_plain subset_add subset_remove hint_status
				shift 2
				;;
			--subset=*)
				add_subset_categories_or_exit "${1#--subset=}" subset_plain subset_add subset_remove hint_status
				shift
				;;
			-i|--include)
				if (($# < 2)); then
					printf 'Option %s requires a value.\n\n' "$1" >&2
					usage_hint_status
					exit 1
				fi
				included_patterns+=("$2")
				shift 2
				;;
			--include=*)
				included_patterns+=("${1#--include=}")
				shift
				;;
			-I|--include-from)
				if (($# < 2)); then
					printf 'Option %s requires a file path.\n\n' "$1" >&2
					usage_hint_status
					exit 1
				fi
				load_pattern_file "$2" included_patterns hint_status
				shift 2
				;;
			--include-from=*)
				load_pattern_file "${1#--include-from=}" included_patterns hint_status
				shift
				;;
			-x|--exclude)
				if (($# < 2)); then
					printf 'Option %s requires a value.\n\n' "$1" >&2
					usage_hint_status
					exit 1
				fi
				excluded_patterns+=("$2")
				shift 2
				;;
			--exclude=*)
				excluded_patterns+=("${1#--exclude=}")
				shift
				;;
			-X|--exclude-from)
				if (($# < 2)); then
					printf 'Option %s requires a file path.\n\n' "$1" >&2
					usage_hint_status
					exit 1
				fi
				load_pattern_file "$2" excluded_patterns hint_status
				shift 2
				;;
			--exclude-from=*)
				load_pattern_file "${1#--exclude-from=}" excluded_patterns hint_status
				shift
				;;
			-h|--help)
				usage_status
				exit 0
				;;
			-*)
				printf 'Unknown option for status: %s\n\n' "$1" >&2
				usage_hint_status
				exit 1
				;;
			*)
				_positional_args+=("$1")
				shift
				;;
		esac
	done
	set -- "${_positional_args[@]}"

	if (($# > 2)); then
		printf 'status accepts at most two arguments.\n\n' >&2
		usage_hint_status
		exit 1
	fi

	# Expand bare @ shorthand:
	#   @           → <default_remote> @<default_remote>
	#   <remote> @  → <remote> @<remote>
	#   @ <remote>  → @<remote> <remote>
	# Not supported with --tags (use "git sync status -t" instead).
	if ((tags_mode == 1)); then
		if (($# == 1)) && [[ "$1" == '@' ]]; then
			printf 'Bare @ is not supported with --tags. Use "git sync status -t" to compare local tags against the default remote.\n\n' >&2
			usage_hint_status
			exit 1
		elif (($# == 2)) && { [[ "$1" == '@' ]] || [[ "$2" == '@' ]]; }; then
			printf 'Bare @ is not supported with --tags. Use "git sync status -t" to compare local tags against the default remote.\n\n' >&2
			usage_hint_status
			exit 1
		fi
	fi
	if (($# == 1)) && [[ "$1" == '@' ]]; then
		local default_remote
		if ! default_remote="$(resolve_default_remote)"; then
			printf 'Cannot determine default remote. Set an upstream or specify a remote.\n\n' >&2
			usage_hint_status
			exit 1
		fi
		set -- "$default_remote" "@${default_remote}"
	elif (($# == 2)); then
		if [[ "$1" == '@' && "$2" == '@' ]]; then
			printf 'Cannot use bare @ for both arguments.\n\n' >&2
			usage_hint_status
			exit 1
		elif [[ "$1" == '@' ]]; then
			set -- "@${2#@}" "$2"
		elif [[ "$2" == '@' ]]; then
			set -- "$1" "@${1#@}"
		fi
	fi

	if ((name_only == 1)) && ((porcelain == 1)); then
		printf 'Options --name-only and --porcelain are mutually exclusive.\n\n' >&2
		usage_hint_status
		exit 1
	fi

	if ((tag_type != 0)) && ((tags_mode == 0)); then
		printf 'Options --annotated and --lightweight require --tags.\n\n' >&2
		usage_hint_status
		exit 1
	fi


	local remote_a_ref=''
	local remote_b_ref=''
	local remote_a_name=''
	local remote_b_name=''
	local remote_a_source=''
	local remote_b_source=''

	if (($# == 0)); then
		local default_remote
		if ! default_remote="$(resolve_default_remote)"; then
			printf 'Cannot determine default remote. Set an upstream or specify a remote.\n\n' >&2
			usage_hint_status
			exit 1
		fi
		remote_a_ref='working copy'
		remote_a_source='worktree'
		if ((tags_mode == 1)); then
			remote_b_ref="@${default_remote}"
			parse_remote_ref "$remote_b_ref" remote_b_name remote_b_source hint_status
		else
			remote_b_ref="$default_remote"
			parse_remote_ref "$remote_b_ref" remote_b_name remote_b_source hint_status
		fi
	elif (($# == 1)); then
		remote_a_ref='working copy'
		remote_a_source='worktree'
		remote_b_ref="$1"
		parse_remote_ref "$remote_b_ref" remote_b_name remote_b_source hint_status
	else
		remote_a_ref="$1"
		remote_b_ref="$2"
		parse_remote_ref "$remote_a_ref" remote_a_name remote_a_source hint_status
		parse_remote_ref "$remote_b_ref" remote_b_name remote_b_source hint_status
	fi

	# In tags mode, force remote source for both sides (ls-remote).
	# Accept plain names — @ prefix is optional for tags.
	if ((tags_mode == 1)); then
		local _a_was_local=0 _b_was_local=0
		if [[ "$remote_a_source" != 'remote' ]] && [[ "$remote_a_source" != 'worktree' ]]; then
			remote_a_source='remote'
			_a_was_local=1
		fi
		if [[ "$remote_b_source" != 'remote' ]]; then
			remote_b_source='remote'
			_b_was_local=1
		fi
		# Warn when mixing @ and plain in a two-arg invocation.
		if [[ "$remote_a_source" != 'worktree' ]] && ((_a_was_local != _b_was_local)) && ((porcelain == 0)); then
			printf 'Note: tags are always queried via ls-remote; @ prefix is optional.\n' >&2
		fi
	fi

	# Determine direction mode: full, ahead-only, behind-only, or none.
	# full:         both sides local — behind/ahead/diverged all reliable.
	# ahead-only:   B is local — only ahead reliably detectable.
	# behind-only:  A is local — only behind reliably detectable.
	# none:         both @remote or tags — no direction classification.
	if ((tags_mode == 0)); then
		local _a_local=0 _b_local=0
		if [[ "$remote_a_source" == 'local' ]] || [[ "$remote_a_source" == 'worktree' ]]; then
			_a_local=1
		fi
		if [[ "$remote_b_source" == 'local' ]]; then
			_b_local=1
		fi
		if ((_a_local == 1)) && ((_b_local == 1)); then
			direction_mode='full'
		elif ((_b_local == 1)); then
			direction_mode='ahead-only'
		elif ((_a_local == 1)); then
			direction_mode='behind-only'
		fi
	fi

	# Resolve subset_filters from +/- modifiers if --subset was specified.
	if ((${#subset_plain[@]} > 0)) || ((${#subset_add[@]} > 0)) || ((${#subset_remove[@]} > 0)); then
		local -A subset_defaults=()
		subset_defaults[missing]=1
		subset_defaults[new]=1
		case "$direction_mode" in
			full)
				subset_defaults[behind]=1
				subset_defaults[ahead]=1
				subset_defaults[diverged]=1
				;;
			ahead-only)
				subset_defaults[ahead]=1
				subset_defaults[different]=1
				;;
			behind-only)
				subset_defaults[behind]=1
				subset_defaults[different]=1
				;;
			*)
				subset_defaults[different]=1
				;;
		esac
		resolve_subset_filters subset_plain subset_add subset_remove subset_defaults subset_filters
	fi

	if ((${#subset_filters[@]} > 0)); then
		# Validate category legality based on direction mode.
		if [[ "$direction_mode" == 'none' ]] && { [[ -n "${subset_filters[behind]+x}" ]] || [[ -n "${subset_filters[ahead]+x}" ]] || [[ -n "${subset_filters[diverged]+x}" ]]; }; then
			if ((tags_mode == 1)); then
				printf 'Categories behind, ahead and diverged are unavailable with --tags.\n\n' >&2
			else
				printf 'Categories behind, ahead and diverged require local refs for at least one side.\n\n' >&2
			fi
			usage_hint_status
			exit 1
		fi
		if [[ "$direction_mode" == 'ahead-only' ]] && { [[ -n "${subset_filters[behind]+x}" ]] || [[ -n "${subset_filters[diverged]+x}" ]]; }; then
			printf 'Categories behind and diverged require local refs on both sides.\n\n' >&2
			usage_hint_status
			exit 1
		fi
		if [[ "$direction_mode" == 'behind-only' ]] && { [[ -n "${subset_filters[ahead]+x}" ]] || [[ -n "${subset_filters[diverged]+x}" ]]; }; then
			printf 'Categories ahead and diverged require local refs on both sides.\n\n' >&2
			usage_hint_status
			exit 1
		fi
		if [[ "$direction_mode" == 'full' ]] && [[ -n "${subset_filters[different]+x}" ]]; then
			printf 'Category different is unavailable when both sides have local refs; use behind, ahead, or diverged.\n\n' >&2
			usage_hint_status
			exit 1
		fi
	fi

	# --- Config loading ---
	local -a inc_layers=('') exc_layers=('')
	inc_layers[1]='' exc_layers[1]=''
	inc_layers[2]='' exc_layers[2]=''
	local -a re_exclude=(0 0 0)

	load_config_multi_joined sync.include inc_layers 0 || true
	load_config_multi_joined sync.exclude exc_layers 0 || true
	load_config_multi_joined sync.status.include inc_layers 1 || true
	load_config_multi_joined sync.status.exclude exc_layers 1 || true

	if ((${#included_patterns[@]} > 0)); then
		inc_layers[2]="$(printf '%s\n' "${included_patterns[@]}")"
	fi
	if ((${#excluded_patterns[@]} > 0)); then
		exc_layers[2]="$(printf '%s\n' "${excluded_patterns[@]}")"
	fi

	resolve_patterns inc_layers exc_layers re_exclude

	declare -A ref_map_a=()
	declare -A ref_map_b=()
	load_ref_set "$remote_a_source" "$remote_a_name" "$tags_mode" ref_map_a "$tag_type"
	load_ref_set "$remote_b_source" "$remote_b_name" "$tags_mode" ref_map_b "$tag_type"

	declare -A refs_by_cat=()
	local -A behind_counts=()
	local -A ahead_counts=()

	compute_ref_categories ref_map_a ref_map_b "$direction_mode" inc_layers exc_layers re_exclude refs_by_cat behind_counts ahead_counts
	apply_subset_filters subset_filters refs_by_cat

	local -a categories=(missing new different behind ahead diverged same)
	local cat

	if ((name_only == 1)); then
		for cat in "${categories[@]}"; do
			status_print_name_only "${refs_by_cat[$cat]}"
		done
		return
	fi

	if ((porcelain == 1)); then
		for cat in "${categories[@]}"; do
			print_porcelain_refs "$cat" "${refs_by_cat[$cat]}" ref_map_a ref_map_b behind_counts ahead_counts
		done
		return
	fi

	local expand_threshold=5
	local collapse_threshold=50

	local _cfg_val
	if _cfg_val=$(load_config_scalar sync.status.expand); then
		if [[ "$_cfg_val" =~ ^[0-9]+$ ]]; then
			expand_threshold="$_cfg_val"
		else
			printf 'Invalid value for sync.status.expand: %s (must be integer)\n' "$_cfg_val" >&2
			exit 1
		fi
	fi
	if _cfg_val=$(load_config_scalar sync.status.collapse); then
		if [[ "$_cfg_val" =~ ^[0-9]+$ ]]; then
			collapse_threshold="$_cfg_val"
		else
			printf 'Invalid value for sync.status.collapse: %s (must be integer)\n' "$_cfg_val" >&2
			exit 1
		fi
	fi

	local printed_sections=0

	for cat in "${categories[@]}"; do
		[[ -n "${refs_by_cat[$cat]}" ]] || continue
		local -a _refs=()
		mapfile -t _refs <<< "${refs_by_cat[$cat]}"
		local _count=${#_refs[@]}

		# Determine collapse state.
		local _normally_collapsed=0
		case "$cat" in
			new)
				if [[ "$remote_a_source" == 'worktree' ]] \
						&& [[ -z "${subset_filters[new]+x}" ]]; then
					_normally_collapsed=1
				fi
				;;
			same)
				if [[ -z "${subset_filters[same]+x}" ]]; then
					_normally_collapsed=1
				fi
				;;
		esac

		# Title and color.
		local _title _color
		case "$cat" in
			missing)   _title="Missing: only in ${remote_a_ref}";                      _color="$SECTION_COLOR_MISSING" ;;
			new)       _title="New: only in ${remote_b_ref}";                           _color="$SECTION_COLOR_NEW" ;;
			different) _title="Different: between ${remote_a_ref} and ${remote_b_ref}"; _color="$SECTION_COLOR_DIFFERENT" ;;
			behind)    _title="Behind: ${remote_b_ref} behind ${remote_a_ref}";         _color="$SECTION_COLOR_BEHIND" ;;
			ahead)     _title="Ahead: ${remote_b_ref} ahead of ${remote_a_ref}";        _color="$SECTION_COLOR_AHEAD" ;;
			diverged)  _title="Diverged: between ${remote_a_ref} and ${remote_b_ref}";  _color="$SECTION_COLOR_DIVERGED" ;;
			same)      _title="Same: identical in ${remote_a_ref} and ${remote_b_ref}"; _color="$SECTION_COLOR_SAME" ;;
		esac

		((printed_sections == 0)) || printf '\n'

		if should_show_details "$_normally_collapsed" "$_count" \
				"$expand_threshold" "$collapse_threshold"; then
			# Sort and optionally decorate only when showing detail.
			local -a _sorted=()
			mapfile -t _sorted < <(sort_lines "${_refs[@]}")

			case "$cat" in
				behind|ahead|diverged)
					local -a _decorated=()
					mapfile -t _decorated < <(format_refs_with_counts "$cat" behind_counts ahead_counts "${_sorted[@]}")
					print_section "$_title" "$_color" "${_decorated[@]}"
					;;
				*)
					print_section "$_title" "$_color" "${_sorted[@]}"
					;;
			esac
		else
			printf '%s (%d)\n' "$_title" "$_count"
			printf '  (Use --subset=%s for detailed list.)\n' "$cat"
		fi

		printed_sections=1
	done

	if ((printed_sections == 0)); then
		if ((tags_mode == 1)); then
			printf 'No tags to report.\n'
		else
			printf 'No branches to report.\n'
		fi
	fi
}

verbose_preview() {
	local dry_run="$1"
	local verbose="$2"
	shift 2

	((verbose)) || return 0
	if ((dry_run)); then
		printf 'dry-run: '
	else
		printf 'run: '
	fi
	printf '%q ' "$@"
	printf '\n'
}

align_try_push() {
	local target_remote="$1"
	local ref_name="$2"
	local ref_type="$3"
	local source_hash="$4"
	local force_mode="$5"
	local dry_run="$6"
	local verbose="${7:-0}"

	local -a cmd=(git push)
	case "$force_mode" in
		force) cmd+=(--force) ;;
		lease) cmd+=(--force-with-lease) ;;
	esac
	cmd+=("$target_remote" "${source_hash}:refs/${ref_type}/${ref_name}")

	verbose_preview "$dry_run" "$verbose" "${cmd[@]}"
	((dry_run)) && return 0
	"${cmd[@]}"
}

align_delete_remote_ref() {
	local target_remote="$1"
	local ref_name="$2"
	local ref_type="$3"
	local dry_run="${4:-0}"
	local verbose="${5:-0}"

	local -a cmd=(git push "$target_remote" ":refs/${ref_type}/${ref_name}")

	verbose_preview "$dry_run" "$verbose" "${cmd[@]}"
	((dry_run)) && return 0
	"${cmd[@]}"
}

align_command() {
	local dry_run=0
	local tags_mode=0
	local tag_type=0
	local verbose=0
	local yes_mode=0
	local on_failure='interactive'
	local force_mode='push'
	local -a included_patterns=()
	local -a excluded_patterns=()
	local -A subset_plain=()
	local -A subset_add=()
	local -A subset_remove=()
	local -A subset_filters=()
	local -a _positional_args=()

	while (($# > 0)); do
		# Expand combined short options (e.g., -nvt → -n -v -t)
		if [[ "$1" =~ ^-[a-zA-Z]{2,}$ ]]; then
			local _combined="$1"
			shift
			local _k
			for ((_k = ${#_combined} - 1; _k >= 1; _k--)); do
				set -- "-${_combined:_k:1}" "$@"
			done
		fi
		case "$1" in
			-n|--dry-run)
				dry_run=1
				shift
				;;
			-v|--verbose)
				verbose=1
				shift
				;;
			-t|--tags)
				tags_mode=1
				shift
				;;
			-a|--annotated)
				if ((tag_type == 2)); then
					printf 'Options --annotated and --lightweight are mutually exclusive.\n\n' >&2
					usage_hint_align
					exit 1
				fi
				tag_type=1
				shift
				;;
			-A|--lightweight)
				if ((tag_type == 1)); then
					printf 'Options --annotated and --lightweight are mutually exclusive.\n\n' >&2
					usage_hint_align
					exit 1
				fi
				tag_type=2
				shift
				;;
			-y|--yes)
				yes_mode=1
				shift
				;;
			--on-failure)
				if (($# < 2)); then
					printf 'Option --on-failure requires a value.\n\n' >&2
					usage_hint_align
					exit 1
				fi
				on_failure="$2"
				shift 2
				;;
			--on-failure=*)
				on_failure="${1#--on-failure=}"
				shift
				;;
			-f|--force)
				if [[ "$force_mode" == 'lease' ]]; then
					printf 'Options --force and --force-with-lease are mutually exclusive.\n\n' >&2
					usage_hint_align
					exit 1
				fi
				force_mode='force'
				shift
				;;
			-F|--force-with-lease)
				if [[ "$force_mode" == 'force' ]]; then
					printf 'Options --force and --force-with-lease are mutually exclusive.\n\n' >&2
					usage_hint_align
					exit 1
				fi
				force_mode='lease'
				shift
				;;
			-s|--subset)
				if (($# < 2)); then
					printf 'Option %s requires a value.\n\n' "$1" >&2
					usage_hint_align
					exit 1
				fi
				add_subset_categories_or_exit "$2" subset_plain subset_add subset_remove hint_align
				shift 2
				;;
			--subset=*)
				add_subset_categories_or_exit "${1#--subset=}" subset_plain subset_add subset_remove hint_align
				shift
				;;
			-i|--include)
				if (($# < 2)); then
					printf 'Option %s requires a value.\n\n' "$1" >&2
					usage_hint_align
					exit 1
				fi
				included_patterns+=("$2")
				shift 2
				;;
			--include=*)
				included_patterns+=("${1#--include=}")
				shift
				;;
			-I|--include-from)
				if (($# < 2)); then
					printf 'Option %s requires a file path.\n\n' "$1" >&2
					usage_hint_align
					exit 1
				fi
				load_pattern_file "$2" included_patterns hint_align
				shift 2
				;;
			--include-from=*)
				load_pattern_file "${1#--include-from=}" included_patterns hint_align
				shift
				;;
			-x|--exclude)
				if (($# < 2)); then
					printf 'Option %s requires a value.\n\n' "$1" >&2
					usage_hint_align
					exit 1
				fi
				excluded_patterns+=("$2")
				shift 2
				;;
			--exclude=*)
				excluded_patterns+=("${1#--exclude=}")
				shift
				;;
			-X|--exclude-from)
				if (($# < 2)); then
					printf 'Option %s requires a file path.\n\n' "$1" >&2
					usage_hint_align
					exit 1
				fi
				load_pattern_file "$2" excluded_patterns hint_align
				shift 2
				;;
			--exclude-from=*)
				load_pattern_file "${1#--exclude-from=}" excluded_patterns hint_align
				shift
				;;
			-h|--help)
				usage_align
				exit 0
				;;
			-*)
				printf 'Unknown option for align: %s\n\n' "$1" >&2
				usage_hint_align
				exit 1
				;;
			*)
				_positional_args+=("$1")
				shift
				;;
		esac
	done
	set -- "${_positional_args[@]}"

	# Load on-failure from config (CLI overrides it above if present).
	local _cfg_on_failure
	if _cfg_on_failure=$(load_config_scalar sync.align.on-failure); then
		if [[ "$on_failure" == 'interactive' ]]; then
			on_failure="$_cfg_on_failure"
		fi
	fi

	case "$on_failure" in
		continue|fail-fast|interactive)
			;;
		*)
			printf 'Unknown value for --on-failure: %s\n\n' "$on_failure" >&2
			usage_hint_align
			exit 1
			;;
	esac

	if (($# != 2)); then
		printf 'align requires exactly two arguments: <source> <target>.\n\n' >&2
		usage_hint_align
		exit 1
	fi

	if ((tag_type != 0)) && ((tags_mode == 0)); then
		printf 'Options --annotated and --lightweight require --tags.\n\n' >&2
		usage_hint_align
		exit 1
	fi

	local source_ref="$1"
	local target_ref="$2"
	local source_name=''
	local target_name=''

	if [[ "$source_ref" == @* ]] || [[ "$target_ref" == @* ]]; then
		printf 'The @ prefix is not supported for align. Use plain remote names.\n\n' >&2
		usage_hint_align
		exit 1
	fi

	source_name="$source_ref"
	target_name="$target_ref"

	# Determine direction mode and source_mode/target_mode.
	# Branches: always use local tracking refs, direction=full.
	# Tags: always ls-remote, direction=none.
	local direction_mode='none'
	local source_mode='local'
	local target_mode='local'
	if ((tags_mode == 1)); then
		source_mode='remote'
		target_mode='remote'
	else
		direction_mode='full'
	fi

	# Resolve subset_filters from +/- modifiers if --subset was specified.
	if ((${#subset_plain[@]} > 0)) || ((${#subset_add[@]} > 0)) || ((${#subset_remove[@]} > 0)); then
		local -A subset_defaults=()
		subset_defaults[missing]=1
		if ((tags_mode == 0)); then
			subset_defaults[behind]=1
			subset_defaults[ahead]=1
			subset_defaults[diverged]=1
		else
			subset_defaults[different]=1
		fi
		resolve_subset_filters subset_plain subset_add subset_remove subset_defaults subset_filters
	fi

	if [[ -n "${subset_filters[same]+x}" ]]; then
		if ((tags_mode == 1)); then
			printf 'Category same is unavailable for align; identical tags do not require alignment.\n\n' >&2
		else
			printf 'Category same is unavailable for align; identical branches do not require alignment.\n\n' >&2
		fi
		usage_hint_align
		exit 1
	fi

	# Validate category legality based on direction mode.
	if ((tags_mode == 1)) && { [[ -n "${subset_filters[behind]+x}" ]] || [[ -n "${subset_filters[ahead]+x}" ]] || [[ -n "${subset_filters[diverged]+x}" ]]; }; then
		printf 'Categories behind, ahead and diverged are unavailable with --tags.\n\n' >&2
		usage_hint_align
		exit 1
	fi
	if ((tags_mode == 0)) && [[ -n "${subset_filters[different]+x}" ]]; then
		printf 'Category different is unavailable for branches; use behind, ahead, or diverged.\n\n' >&2
		usage_hint_align
		exit 1
	fi

	# --- Config loading ---
	local -a inc_layers=('') exc_layers=('')
	inc_layers[1]='' exc_layers[1]=''
	inc_layers[2]='' exc_layers[2]=''
	local -a re_exclude=(0 0 0)

	load_config_multi_joined sync.include inc_layers 0 || true
	load_config_multi_joined sync.exclude exc_layers 0 || true
	load_config_multi_joined sync.align.include inc_layers 1 || true
	load_config_multi_joined sync.align.exclude exc_layers 1 || true

	if ((${#included_patterns[@]} > 0)); then
		inc_layers[2]="$(printf '%s\n' "${included_patterns[@]}")"
	fi
	if ((${#excluded_patterns[@]} > 0)); then
		exc_layers[2]="$(printf '%s\n' "${excluded_patterns[@]}")"
	fi

	resolve_patterns inc_layers exc_layers re_exclude

	declare -A ref_map_a=()
	declare -A ref_map_b=()
	load_ref_set "$source_mode" "$source_name" "$tags_mode" ref_map_a "$tag_type"
	load_ref_set "$target_mode" "$target_name" "$tags_mode" ref_map_b "$tag_type"

	declare -A refs_by_cat=()
	declare -A behind_counts=()
	declare -A ahead_counts=()

	compute_ref_categories ref_map_a ref_map_b "$direction_mode" inc_layers exc_layers re_exclude refs_by_cat behind_counts ahead_counts
	apply_subset_filters subset_filters refs_by_cat

	# Exclude new (deletions) by default unless --subset new.
	if [[ -z "${subset_filters[new]+x}" ]]; then
		refs_by_cat[new]=''
	fi

	# Build candidates list and reverse lookup from refs_by_cat.
	declare -A category_by_ref=()
	local -a candidates=()
	local _cat _ref
	for _cat in missing new different behind ahead diverged; do
		[[ -n "${refs_by_cat[$_cat]}" ]] || continue
		local -a _cat_refs=()
		mapfile -t _cat_refs <<< "${refs_by_cat[$_cat]}"
		for _ref in "${_cat_refs[@]}"; do
			candidates+=("$_ref")
			category_by_ref["$_ref"]="$_cat"
		done
	done

	if ((${#candidates[@]} > 0)); then
		mapfile -t candidates < <(sort_lines "${candidates[@]}")
	fi

	if ((${#candidates[@]} == 0)); then
		if ((tags_mode == 1)); then
			printf 'No tags to align.\n'
		else
			printf 'No branches to align.\n'
		fi
		return 0
	fi

	local pushed=0
	local deleted=0
	local forced=0
	local skipped=0
	local failed=0
	local abort_all=0
	local source_hash action category current_mode answer
	local push_label='branch'
	if ((tags_mode == 1)); then
		push_label='tag'
	fi

	local ref_type='heads'
	if ((tags_mode)); then
		ref_type='tags'
	fi

	for ref in "${candidates[@]}"; do
		category="${category_by_ref[$ref]}"
		current_mode="$force_mode"
		source_hash=''
		action='push'

		if [[ "$category" == 'new' ]]; then
			source_hash="${ref_map_b[$ref]}"
			action='delete'
		else
			source_hash="${ref_map_a[$ref]}"
			case "$category" in
				missing)  action='push' ;;
				behind)   action='forward' ;;
				*)        action="$current_mode" ;;
			esac
		fi

		printf '%s\t%s\t%s\t%s\n' "$category" "$action" "$ref" "$source_hash"

		# Confirm before deleting unless --yes or --dry-run.
		if [[ "$category" == 'new' ]] && ((dry_run == 0)) && ((yes_mode == 0)); then
			if is_interactive_tty; then
				local confirm=''
				printf 'Delete %s %s from %s? [y]es/[n]o/[a]ll yes/[c]ancel: ' "$push_label" "$ref" "$target_ref" >&2
				if ! IFS= read -r confirm; then
					confirm='c'
				fi
				case "$confirm" in
					y|Y) : ;;
					a|A)
						yes_mode=1
						;;
					n|N)
						((skipped += 1))
						printf 'skipped\t%s\t%s\n' "$category" "$ref"
						continue
						;;
					c|C)
						printf 'Cancelled by user.\n' >&2
						abort_all=1
						break
						;;
					*)
						printf 'Unknown choice: %s — skipping.\n' "$confirm" >&2
						((skipped += 1))
						printf 'skipped\t%s\t%s\n' "$category" "$ref"
						continue
						;;
				esac
			else
				printf 'Refusing to delete %s %s without confirmation (non-interactive, use --yes).\n' "$push_label" "$ref" >&2
				((skipped += 1))
				printf 'skipped\t%s\t%s\n' "$category" "$ref"
				continue
			fi
		fi

		while true; do
			local failure_mode="$current_mode"
			local op_ok=true

			if [[ "$category" == 'new' ]]; then
				failure_mode='delete'
				align_delete_remote_ref "$target_name" "$ref" "$ref_type" "$dry_run" "$verbose" || op_ok=false
			else
				align_try_push "$target_name" "$ref" "$ref_type" "$source_hash" "$current_mode" "$dry_run" "$verbose" || op_ok=false
			fi

			if $op_ok; then
				if [[ "$category" == 'new' ]]; then
					((deleted += 1))
				elif [[ "$current_mode" == 'push' ]]; then
					((pushed += 1))
				else
					((forced += 1))
				fi
				if ((dry_run == 0)); then
					printf 'done: %s\n' "$ref"
				fi
				break
			fi

			if [[ "$on_failure" == 'fail-fast' ]]; then
				((failed += 1))
				abort_all=1
				printf 'failed: %s (%s)\n' "$ref" "$failure_mode" >&2
				break
			fi

			if [[ "$on_failure" == 'continue' ]]; then
				((failed += 1))
				printf 'failed: %s (%s)\n' "$ref" "$failure_mode" >&2
				break
			fi

			if ! is_interactive_tty; then
				((failed += 1))
				printf 'failed: %s (%s, non-interactive)\n' "$ref" "$failure_mode" >&2
				break
			fi

			if [[ "$category" == 'new' ]]; then
				((failed += 1))
				printf 'failed: %s (%s)\n' "$ref" "$failure_mode" >&2
				printf 'hint: Delete failures are server-side; force/lease do not apply to deletions.\n' >&2
				printf 'hint: If the branch is the remote current branch (HEAD), deletion is denied by the remote.\n' >&2
				break
			fi

			printf 'Push failed for %s %s (%s). [r]etry/[p]ush/[f]orce/[l]ease/[s]kip/[c]ancel: ' "$push_label" "$ref" "$category" >&2
			if ! IFS= read -r answer; then
				answer='c'
			fi
			case "$answer" in
				r|R) : ;;
				p|P) current_mode='push' ;;
				f|F) current_mode='force' ;;
				l|L) current_mode='lease' ;;
				s|S)
					((skipped += 1))
					printf 'skipped\t%s\t%s\n' "$category" "$ref"
					break
					;;
				c|C)
					((failed += 1))
					abort_all=1
					printf 'failed: %s (%s)\n' "$ref" "$failure_mode" >&2
					break
					;;
				*)
					printf 'Unknown choice: %s\n' "$answer" >&2
					;;
			esac
		done

		if ((abort_all == 1)); then
			break
		fi
	done

	printf '\n'
	if ((dry_run == 1)); then
		printf 'Plan\n'
		printf '\t%d to delete\n' "$deleted"
		printf '\t%d to push\n' "$pushed"
		printf '\t%d to force\n' "$forced"
	else
		printf 'Summary\n'
		printf '\t%d deleted\n' "$deleted"
		printf '\t%d pushed\n' "$pushed"
		printf '\t%d forced\n' "$forced"
		printf '\t%d skipped\n' "$skipped"
		printf '\t%d failed\n' "$failed"
	fi

	if ((failed > 0)); then
		return 1
	fi

	return 0
}

main() {
	if (($# == 0)); then
		usage_main
		exit 1
	fi

	local command="$1"
	shift

	case "$command" in
		status)
			status_command "$@"
			;;
		align)
			align_command "$@"
			;;
		-h|--help)
			usage_main
			;;
		--version)
			printf 'git-sync version %s\n' "$GIT_SYNC_VERSION"
			;;
		*)
			printf 'Unknown command: %s\n\n' "$command" >&2
			usage_main
			exit 1
			;;
	esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	main "$@"
fi
