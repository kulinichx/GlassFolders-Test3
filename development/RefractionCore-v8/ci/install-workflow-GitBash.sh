#!/usr/bin/env bash
# Run in existing worktree, only AFTER staging/copying the independent module.
set -euo pipefail
export GIT_PAGER=cat
[[ -e .git && -f control ]] || { echo 'STOP: not at GlassFolders worktree root' >&2; exit 1; }
SOURCE='development/RefractionCore-v8/ci/gf-refractioncore-v8.yml'
DEST='.github/workflows/gf-refractioncore-v8.yml'
[[ -f "$SOURCE" ]] || { echo 'STOP: install v8 source first' >&2; exit 1; }
[[ ! -e "$DEST" ]] || { echo 'STOP: workflow exists; will not overwrite' >&2; exit 1; }
[[ ! -n "$(git status --porcelain -- "$DEST")" ]] || { echo 'STOP: existing target changes' >&2; exit 1; }
mkdir -p .github/workflows
cp "$SOURCE" "$DEST"
git add -- "$DEST"
git -c core.whitespace=cr-at-eol diff --cached --check -- "$DEST"
git --no-pager diff --cached --stat -- "$DEST"
echo 'Workflow staged (not committed or pushed); will run on GitHub macOS after push.'
