#!/usr/bin/env bash
set -euo pipefail
export GIT_PAGER=cat
# Run FROM the current GlassFolders worktree. Never cd to the original clone,
# create branches, reset/stash, or modify tests/issuer.
if [[ ! -e .git || ! -f control ]]; then
    echo 'STOP: 先 cd 到 GlassFolders 工作树根目录（必须存在 .git 和 control）' >&2
    exit 1
fi
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST='development/RefractionCore-v8'
if [[ -e "$DEST" ]]; then
    echo "STOP: $DEST 已存在，避免重复覆盖" >&2
    exit 1
fi
if [[ -n "$(git status --porcelain -- "$DEST")" ]]; then
    echo 'STOP: 目标路径含有未提交文件' >&2
    exit 1
fi
# The preflight handles missing NumPy/Pillow inside an isolated, temporary venv.
# On Windows Git Bash Python may be 'python' rather than 'python3'.
if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN=python3
elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN=python
else
    echo 'STOP: no Python 3 interpreter found (install Python 3.11–3.14)' >&2
    exit 1
fi
"$PYTHON_BIN" "$SOURCE_DIR/tools/run-tests.py"
mkdir -p development
cp -R "$SOURCE_DIR" "$DEST"
# Avoid Python cache or generated demo files being staged accidentally.
find "$DEST" -type d -name __pycache__ -prune -exec rm -rf {} +
git add -- "$DEST"
git -c core.whitespace=cr-at-eol diff --cached --check -- "$DEST"
git --no-pager diff --cached --stat -- "$DEST"
echo 'V8.0.2-dev SOURCE STAGED. Did not modify plugin version, settings, hooks or issuer.'
echo 'This is a separate library; iPad visual output will NOT change yet.'
echo 'Optional compile in a Theos CI: make -C development/RefractionCore-v8'
