#!/usr/bin/env bash
# Copyright (C) 2026 Julien Cochuyt (https://github.com/JulienCochuyt)
# SPDX-License-Identifier: GPL-2.0-only
# Git fixture helpers for integration tests.

# Create a bare repo that acts as a "remote".
# Usage: create_bare_remote <path>
create_bare_remote() {
	local path="$1"
	git init --bare "$path" >/dev/null 2>&1
}

# Create a working repo with an initial commit.
# Usage: create_work_repo <path>
create_work_repo() {
	local path="$1"
	git init -b main "$path" >/dev/null 2>&1
	git -C "$path" commit --allow-empty -m 'initial' >/dev/null 2>&1
}

# Add a remote and fetch tracking refs.
# Usage: add_and_fetch <work_repo> <remote_name> <bare_repo_path>
add_and_fetch() {
	local work="$1"
	local name="$2"
	local url="$3"
	git -C "$work" remote add "$name" "$url" 2>/dev/null || true
	git -C "$work" fetch "$name" --prune >/dev/null 2>&1 || true
}

# Create a commit on the current branch of a repo. Returns the commit hash.
# Usage: hash=$(make_commit <repo> [message])
make_commit() {
	local repo="$1"
	local msg="${2:-commit}"
	git -C "$repo" commit --allow-empty -m "$msg" >/dev/null 2>&1
	git -C "$repo" rev-parse HEAD
}

# Create a branch pointing at a specific commit.
# Usage: create_branch <repo> <branch_name> [commit]
create_branch() {
	local repo="$1"
	local branch="$2"
	local commit="${3:-HEAD}"
	git -C "$repo" branch "$branch" "$commit" 2>/dev/null || \
		git -C "$repo" branch -f "$branch" "$commit"
}

# Push a branch from work repo to a bare remote.
# Usage: push_branch <work_repo> <remote_name> <branch>
push_branch() {
	local repo="$1"
	local remote="$2"
	local branch="$3"
	git -C "$repo" push "$remote" "${branch}:refs/heads/${branch}" --force >/dev/null 2>&1
}

# Push a tag from work repo to a bare remote.
# Usage: push_tag <work_repo> <remote_name> <tag>
push_tag() {
	local repo="$1"
	local remote="$2"
	local tag="$3"
	git -C "$repo" push "$remote" "refs/tags/${tag}:refs/tags/${tag}" --force >/dev/null 2>&1
}

# Create a lightweight tag.
# Usage: create_lightweight_tag <repo> <tag_name> [commit]
create_lightweight_tag() {
	local repo="$1"
	local tag="$2"
	local commit="${3:-HEAD}"
	git -C "$repo" tag -f "$tag" "$commit" >/dev/null 2>&1
}

# Create an annotated tag.
# Usage: create_annotated_tag <repo> <tag_name> [commit] [message]
create_annotated_tag() {
	local repo="$1"
	local tag="$2"
	local commit="${3:-HEAD}"
	local msg="${4:-tag $tag}"
	git -C "$repo" tag -f -a "$tag" -m "$msg" "$commit" >/dev/null 2>&1
}

# Make a bare repo reject all pushes (for failure tests).
# Usage: lock_bare_repo <bare_repo_path>
lock_bare_repo() {
	local path="$1"
	cat > "${path}/hooks/pre-receive" <<'HOOK'
#!/bin/sh
echo "push rejected by test hook" >&2
exit 1
HOOK
	chmod +x "${path}/hooks/pre-receive"
}

# Unlock a previously locked bare repo.
# Usage: unlock_bare_repo <bare_repo_path>
unlock_bare_repo() {
	local path="$1"
	rm -f "${path}/hooks/pre-receive"
}
