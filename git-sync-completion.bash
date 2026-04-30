#!/usr/bin/env bash
# Bash completion for git-sync.sh
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
#
# Source this file to enable completion:
#   source /path/to/git-sync-completion.bash
#
# To persist, add the above line to ~/.bashrc (Linux/macOS) or
# ~/.bash_profile (Git for Windows).
# If bash-completion is installed, you may also copy this file to its
# completions directory (e.g. /etc/bash_completion.d/ on Linux,
# $(brew --prefix)/etc/bash_completion.d/ on macOS with Homebrew).

_git_sync_remotes() {
	if declare -f __git_remotes >/dev/null 2>&1; then
		__git_remotes
	else
		git remote 2>/dev/null
	fi
}

_git_sync_refs() {
	local mode="$1"
	if [[ "$mode" == "tags" ]]; then
		if declare -f __git_tags >/dev/null 2>&1; then
			__git_tags
		else
			git tag -l 2>/dev/null
		fi
	else
		if declare -f __git_heads >/dev/null 2>&1; then
			__git_heads
		else
			git for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null
		fi
	fi
}

_git_sync_complete_subset() {
	local cur_value="$1" subcommand="$2"
	local categories="new missing different same behind ahead diverged"
	[[ "$subcommand" == "align" ]] && categories="new missing different behind ahead diverged"

	# Strip prefix already typed (everything up to and including the last comma)
	local prefix="" stem="$cur_value"
	if [[ "$cur_value" == *,* ]]; then
		prefix="${cur_value%,*},"
		stem="${cur_value##*,}"
	fi

	# Strip +/- prefix from stem
	local sign=""
	if [[ "$stem" == +* || "$stem" == -* ]]; then
		sign="${stem:0:1}"
		stem="${stem:1}"
	fi

	# Generate candidates with the sign prefix
	local -a candidates=()
	local cat
	for cat in $categories; do
		candidates+=("${sign}${cat}")
	done

	# Match candidates against the typed stem
	if [[ -z "${sign}${stem}" ]]; then
		# Empty input: return all candidates
		COMPREPLY=("${candidates[@]}")
	else
		COMPREPLY=($(compgen -W "${candidates[*]}" -- "${sign}${stem}"))
	fi
	# Prepend the comma-separated prefix to each match
	if [[ -n "$prefix" ]]; then
		COMPREPLY=("${COMPREPLY[@]/#/$prefix}")
	fi
}

_git_sync() {
	local cur prev
	local -a words
	local cword

	# Use _init_completion if available (bash-completion package),
	# otherwise fall back to raw COMP_ variables.
	if declare -f _init_completion >/dev/null 2>&1; then
		_init_completion || return
	else
		cur="${COMP_WORDS[COMP_CWORD]}"
		prev="${COMP_WORDS[COMP_CWORD-1]}"
		words=("${COMP_WORDS[@]}")
		cword=$COMP_CWORD
	fi

	# Handle '=' from COMP_WORDBREAKS splitting.
	# Case 1: cursor is on "=" itself (prev is the option, cur is "=")
	# Case 2: cursor is after "=" (prev is "=", cur is the typed value)
	if [[ "$cur" == "=" ]]; then
		prev="${prev}"  # prev is already the option name
		cur=""
	elif [[ "$prev" == "=" ]]; then
		prev="${words[cword-2]}"
	fi

	local subcommand=""
	local has_tags=0
	local i

	# Find subcommand and check for --tags/-t
	for ((i = 1; i < cword; i++)); do
		case "${words[i]}" in
			status|align)
				[[ -z "$subcommand" ]] && subcommand="${words[i]}"
				;;
			-t|--tags)
				has_tags=1
				;;
			-s|--subset|-i|--include|-x|--exclude|-I|--include-from|-X|--exclude-from|--on-failure)
				# Skip the next word (option argument)
				((i++))
				;;
			=)
				# Skip '=' inserted by COMP_WORDBREAKS splitting
				;;
			-*)
				# Check combined short opts for -t
				if [[ "${words[i]}" =~ ^-[a-zA-Z]*t[a-zA-Z]*$ ]]; then
					has_tags=1
				fi
				;;
		esac
	done

	# Determine ref mode for pattern completion
	local ref_mode="branches"
	((has_tags)) && ref_mode="tags"

	# Handle option arguments
	case "$prev" in
		-s|--subset)
			compopt -o nospace 2>/dev/null
			_git_sync_complete_subset "$cur" "$subcommand"
			return
			;;
		--on-failure)
			COMPREPLY=($(compgen -W "continue fail-fast interactive" -- "$cur"))
			return
			;;
		-i|--include|-x|--exclude)
			COMPREPLY=($(compgen -W "$(_git_sync_refs "$ref_mode")" -- "$cur"))
			return
			;;
		-I|--include-from|-X|--exclude-from)
			if declare -f _filedir >/dev/null 2>&1; then
				_filedir
			else
				COMPREPLY=($(compgen -f -- "$cur"))
			fi
			return
			;;
	esac

	# Complete options
	if [[ "$cur" == -* ]]; then
		case "$subcommand" in
			status)
				COMPREPLY=($(compgen -W "
					-h --help
					-p --porcelain --name-only
					-t --tags -a --annotated -A --lightweight
					-s --subset=
					-i --include= -I --include-from=
					-x --exclude= -X --exclude-from=
				" -- "$cur"))
				;;
			align)
				COMPREPLY=($(compgen -W "
					-h --help
					-n --dry-run -v --verbose -y --yes
					-t --tags -a --annotated -A --lightweight
					-f --force -F --force-with-lease
					-s --subset= --on-failure=
					-i --include= -I --include-from=
					-x --exclude= -X --exclude-from=
				" -- "$cur"))
				;;
			*)
				COMPREPLY=($(compgen -W "-h --help --version" -- "$cur"))
				;;
		esac
		# Suppress trailing space when any result ends with =
		local r
		for r in "${COMPREPLY[@]}"; do
			if [[ "$r" == *= ]]; then
				compopt -o nospace 2>/dev/null
				break
			fi
		done
		return
	fi

	# Complete positional arguments
	if [[ -z "$subcommand" ]]; then
		COMPREPLY=($(compgen -W "status align" -- "$cur"))
		return
	fi

	# Positional args are remotes (with optional @ prefix)
	local remotes
	remotes=$(_git_sync_remotes)
	if [[ "$cur" == @* ]]; then
		# Prefix each remote with @
		local at_remotes
		at_remotes=$(printf "@%s\n" $remotes)
		COMPREPLY=($(compgen -W "$at_remotes" -- "$cur"))
	else
		COMPREPLY=($(compgen -W "$remotes" -- "$cur"))
	fi
}

complete -F _git_sync git-sync.sh
complete -F _git_sync git-sync
