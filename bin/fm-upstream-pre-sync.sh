#!/usr/bin/env bash
# Build a pre-sync risk report against an upstream branch.
#
# Use this before applying source-repo updates into the local clone.
# The report shows incoming commits, local-only commits, overlap between
# incoming and local change footprints, and a recommendation.
#
# This script is read-only with one optional network step.
# By default it runs `git fetch <remote>`.
# Use --no-fetch to skip the network refresh and report from local refs.
#
# Usage:
#   bin/fm-upstream-pre-sync.sh [--remote <name>] [--base <branch>] [--no-fetch]
set -eu

usage() {
  cat <<'EOF'
usage: fm-upstream-pre-sync.sh [--remote <name>] [--base <branch>] [--no-fetch] [--help]
EOF
}

REMOTE=upstream
BASE=main
DO_FETCH=1

while [ $# -gt 0 ]; do
  case "$1" in
    --remote)
      [ $# -ge 2 ] || { usage >&2; exit 1; }
      REMOTE=$2
      shift 2
      ;;
    --base)
      [ $# -ge 2 ] || { usage >&2; exit 1; }
      BASE=$2
      shift 2
      ;;
    --no-fetch)
      DO_FETCH=0
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

git rev-parse --git-dir >/dev/null 2>&1 || {
  echo "error: not inside a git repository" >&2
  exit 2
}

if ! git remote get-url "$REMOTE" >/dev/null 2>&1; then
  echo "error: remote '$REMOTE' is not configured" >&2
  echo "hint: git remote add $REMOTE <source-repo-url>" >&2
  exit 2
fi

if [ "$DO_FETCH" -eq 1 ]; then
  if ! git fetch --quiet "$REMOTE"; then
    echo "error: failed to fetch '$REMOTE'" >&2
    exit 2
  fi
fi

TARGET_REF="$REMOTE/$BASE"
if ! git rev-parse --verify "$TARGET_REF" >/dev/null 2>&1; then
  echo "error: target ref '$TARGET_REF' is not available locally" >&2
  echo "hint: fetch the remote, or choose an existing remote branch with --base" >&2
  exit 2
fi

HEAD_LABEL=$(git symbolic-ref --short -q HEAD || git rev-parse --short HEAD)
MERGE_BASE=$(git merge-base HEAD "$TARGET_REF")
INCOMING_COUNT=$(git rev-list --count "HEAD..$TARGET_REF")
LOCAL_ONLY_COUNT=$(git rev-list --count "$TARGET_REF..HEAD")
WORKTREE_DIRTY=no
[ -z "$(git status --porcelain)" ] || WORKTREE_DIRTY=yes

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/fm-upstream-pre-sync.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT INT TERM HUP QUIT

incoming_files="$tmpdir/incoming-files.txt"
local_files="$tmpdir/local-files.txt"
overlap_files="$tmpdir/overlap-files.txt"
touch "$incoming_files" "$local_files" "$overlap_files"

git diff --name-only "$MERGE_BASE..$TARGET_REF" | sort -u > "$incoming_files"
git diff --name-only "$MERGE_BASE..HEAD" | sort -u > "$local_files"
comm -12 "$incoming_files" "$local_files" > "$overlap_files" || true

INCOMING_FILE_COUNT=$(wc -l < "$incoming_files" | tr -d ' ')
LOCAL_FILE_COUNT=$(wc -l < "$local_files" | tr -d ' ')
OVERLAP_COUNT=$(wc -l < "$overlap_files" | tr -d ' ')
CALM_OVERLAP_COUNT=$(grep -E -c '(^|/)(calm|fm-turnend-guard-cursor\.sh|fm-cursor-primary\.test\.sh)' "$overlap_files" || true)

echo "PRE-SYNC REPORT"
echo "repo: $(git rev-parse --show-toplevel)"
echo "current: $HEAD_LABEL"
echo "remote: $REMOTE"
echo "base: $BASE"
echo "target-ref: $TARGET_REF"
echo "fetched: $([ "$DO_FETCH" -eq 1 ] && printf yes || printf no)"
echo "merge-base: $MERGE_BASE"
echo "incoming-commits: $INCOMING_COUNT"
echo "local-only-commits: $LOCAL_ONLY_COUNT"
echo "worktree-dirty: $WORKTREE_DIRTY"
echo

echo "INCOMING COMMITS (up to 20)"
if [ "$INCOMING_COUNT" -eq 0 ]; then
  echo "(none)"
else
  git log --oneline --no-decorate -n 20 "HEAD..$TARGET_REF"
fi
echo

echo "LOCAL-ONLY COMMITS (up to 20)"
if [ "$LOCAL_ONLY_COUNT" -eq 0 ]; then
  echo "(none)"
else
  git log --oneline --no-decorate -n 20 "$TARGET_REF..HEAD"
fi
echo

echo "FILE FOOTPRINT"
echo "incoming-files: $INCOMING_FILE_COUNT"
echo "local-files: $LOCAL_FILE_COUNT"
echo "overlap-files: $OVERLAP_COUNT"
echo "calm-overlap-files: $CALM_OVERLAP_COUNT"
echo

echo "OVERLAP FILES (up to 50)"
if [ "$OVERLAP_COUNT" -eq 0 ]; then
  echo "(none)"
else
  sed -n '1,50p' "$overlap_files"
fi
echo

echo "RECOMMENDATION"
if [ "$INCOMING_COUNT" -eq 0 ]; then
  echo "no upstream commits are pending."
  echo "result: no sync action needed."
elif [ "$OVERLAP_COUNT" -gt 0 ]; then
  echo "incoming work overlaps files you also changed locally."
  echo "result: manual reconcile required before merge or cherry-pick."
elif [ "$WORKTREE_DIRTY" = yes ]; then
  echo "incoming work does not overlap your local commit footprint."
  echo "result: review commits, then sync only after you commit your current local edits."
else
  echo "incoming work does not overlap your local commit footprint."
  echo "result: low-risk fast-forward candidate after commit review."
fi
