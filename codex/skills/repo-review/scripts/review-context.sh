#!/usr/bin/env bash
#
# review-context.sh — read-only committed-range context for the repo-review skill.
#
# Usage:
#   review-context.sh <repo-path> <base..head> [--autofix]
#
# The script resolves moving refs to immutable object IDs, reports guidance files,
# changed files, and diff stat, and gates autofix safety. It never edits, stages,
# commits, switches branches, or writes into the target repo.

set -uo pipefail

EMPTY_TREE="4b825dc642cb6eb9a060e54bf8d69288fbee4904"
AUTOFIX=0

usage() {
  echo "usage: $0 <repo-path> <base..head> [--autofix]" >&2
}

die() {
  echo "error: $*" >&2
  exit 1
}

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  usage
  exit 2
fi

REPO_INPUT="$1"
REQUESTED_RANGE="$2"
shift 2

if [ $# -eq 1 ]; then
  case "$1" in
    --autofix) AUTOFIX=1 ;;
    *) usage; exit 2 ;;
  esac
fi

case "$REQUESTED_RANGE" in
  *...*) die "three-dot ranges are ambiguous here; pass an explicit two-dot base..head range" ;;
  *..*) ;;
  *) die "range must use two-dot base..head syntax" ;;
esac

BASE_REF="${REQUESTED_RANGE%%..*}"
HEAD_REF="${REQUESTED_RANGE#*..}"

[ -n "$BASE_REF" ] || die "range base is empty"
[ -n "$HEAD_REF" ] || die "range head is empty"

REPO_ROOT="$(git -C "$REPO_INPUT" rev-parse --show-toplevel 2>/dev/null)" \
  || die "not a git repo: $REPO_INPUT"

resolve_endpoint() {
  local ref="$1"
  local allow_tree="$2"
  local commit_hash tree_hash

  commit_hash="$(git -C "$REPO_ROOT" rev-parse --verify --quiet "${ref}^{commit}" 2>/dev/null)" || commit_hash=""
  if [ -n "$commit_hash" ]; then
    printf 'commit %s\n' "$commit_hash"
    return 0
  fi

  if [ "$allow_tree" = "yes" ]; then
    tree_hash="$(git -C "$REPO_ROOT" rev-parse --verify --quiet "${ref}^{tree}" 2>/dev/null)" || tree_hash=""
    if [ -n "$tree_hash" ]; then
      printf 'tree %s\n' "$tree_hash"
      return 0
    fi
  fi

  return 1
}

base_resolved="$(resolve_endpoint "$BASE_REF" yes)" \
  || die "cannot resolve range base: $BASE_REF"
head_resolved="$(resolve_endpoint "$HEAD_REF" no)" \
  || die "cannot resolve range head commit: $HEAD_REF"

BASE_TYPE="${base_resolved%% *}"
BASE_HASH="${base_resolved#* }"
HEAD_TYPE="${head_resolved%% *}"
HEAD_HASH="${head_resolved#* }"
CURRENT_HEAD="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)" \
  || die "cannot resolve current HEAD"
CURRENT_BRANCH="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null)" || CURRENT_BRANCH=""

if [ -n "$CURRENT_BRANCH" ]; then
  DETACHED_HEAD="no"
else
  DETACHED_HEAD="yes"
fi

MERGE_BASE="n/a"
if [ "$BASE_TYPE" = "commit" ]; then
  if git -C "$REPO_ROOT" merge-base --is-ancestor "$BASE_HASH" "$HEAD_HASH" 2>/dev/null; then
    BASE_IS_ANCESTOR="yes"
  else
    merge_base_status=$?
    [ "$merge_base_status" -eq 1 ] || die "cannot test whether base is an ancestor of head"
    BASE_IS_ANCESTOR="no"
    MERGE_BASE="$(git -C "$REPO_ROOT" merge-base "$BASE_HASH" "$HEAD_HASH" 2>/dev/null)" || MERGE_BASE="(none)"
  fi
elif [ "$BASE_HASH" = "$EMPTY_TREE" ]; then
  BASE_IS_ANCESTOR="yes"
else
  BASE_IS_ANCESTOR="n/a"
fi

if [ "$HEAD_HASH" = "$CURRENT_HEAD" ]; then
  HEAD_IS_CURRENT="yes"
else
  HEAD_IS_CURRENT="no"
fi

PORCELAIN="$(git -C "$REPO_ROOT" status --porcelain)"
if [ -n "$PORCELAIN" ]; then
  WORKTREE="dirty"
else
  WORKTREE="clean"
fi

AUTOFIX_SAFE="n/a"
AUTOFIX_REASON="not-requested"
if [ "$AUTOFIX" -eq 1 ]; then
  if [ "$WORKTREE" != "clean" ]; then
    AUTOFIX_SAFE="no"
    AUTOFIX_REASON="dirty-worktree"
  elif [ "$HEAD_IS_CURRENT" != "yes" ]; then
    AUTOFIX_SAFE="no"
    AUTOFIX_REASON="requested-head-not-current"
  elif [ "$DETACHED_HEAD" = "yes" ]; then
    AUTOFIX_SAFE="no"
    AUTOFIX_REASON="detached-head"
  elif [ "$BASE_TYPE" != "commit" ] && [ "$BASE_HASH" != "$EMPTY_TREE" ]; then
    AUTOFIX_SAFE="no"
    AUTOFIX_REASON="base-not-commit"
  elif [ "$BASE_IS_ANCESTOR" = "no" ]; then
    AUTOFIX_SAFE="no"
    AUTOFIX_REASON="base-not-ancestor"
  else
    AUTOFIX_SAFE="yes"
    AUTOFIX_REASON="clean-current-head"
  fi
fi

GUIDANCE_FILES=""

add_guidance() {
  local abs="$1"
  local rel
  [ -f "$abs" ] || return 0
  rel="${abs#"$REPO_ROOT"/}"
  if [ "$abs" = "$rel" ]; then
    rel="$(basename "$abs")"
  fi
  if ! printf '%s\n' "$GUIDANCE_FILES" | grep -Fxq "$rel"; then
    if [ -n "$GUIDANCE_FILES" ]; then
      GUIDANCE_FILES="${GUIDANCE_FILES}
${rel}"
    else
      GUIDANCE_FILES="$rel"
    fi
  fi
}

add_guidance "$REPO_ROOT/AGENTS.md"
add_guidance "$REPO_ROOT/CLAUDE.md"

CHANGED_NAMES="$(git -C "$REPO_ROOT" diff --name-only "$BASE_HASH" "$HEAD_HASH")" \
  || die "git diff --name-only failed for $BASE_HASH..$HEAD_HASH"

while IFS= read -r changed_path; do
  [ -n "$changed_path" ] || continue
  dir="$(dirname "$changed_path")"
  [ "$dir" = "." ] && dir=""

  while :; do
    prefix=""
    [ -n "$dir" ] && prefix="$dir/"
    add_guidance "$REPO_ROOT/${prefix}AGENTS.md"
    add_guidance "$REPO_ROOT/${prefix}CLAUDE.md"
    [ -z "$dir" ] && break
    case "$dir" in
      */*) dir="${dir%/*}" ;;
      *) dir="" ;;
    esac
  done
done <<EOF_CHANGED
$CHANGED_NAMES
EOF_CHANGED

if [ -n "$GUIDANCE_FILES" ]; then
  while IFS= read -r guidance_rel; do
    [ -n "$guidance_rel" ] || continue
    guidance_dir="$(dirname "$guidance_rel")"
    [ "$guidance_dir" = "." ] && guidance_dir=""
    # Include directly referenced code review docs without scanning the whole repo.
    refs="$(grep -Eio '[[:alnum:]_./-]*code[-_]review\.md' "$REPO_ROOT/$guidance_rel" 2>/dev/null || true)"
    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      case "$ref" in
        /*) add_guidance "$REPO_ROOT/${ref#/}" ;;
        *)
          if [ -n "$guidance_dir" ]; then
            add_guidance "$REPO_ROOT/$guidance_dir/$ref"
          else
            add_guidance "$REPO_ROOT/$ref"
          fi
          ;;
      esac
    done <<EOF_REFS
$refs
EOF_REFS
  done <<EOF_GUIDANCE
$GUIDANCE_FILES
EOF_GUIDANCE
fi

echo "repo-root: $REPO_ROOT"
echo "requested-range: $REQUESTED_RANGE"
echo "base-ref: $BASE_REF"
echo "head-ref: $HEAD_REF"
echo "resolved-base-type: $BASE_TYPE"
echo "resolved-base: $BASE_HASH"
echo "resolved-head-type: $HEAD_TYPE"
echo "resolved-head: $HEAD_HASH"
echo "current-head: $CURRENT_HEAD"
echo "head-is-current: $HEAD_IS_CURRENT"
if [ -n "$CURRENT_BRANCH" ]; then
  echo "branch: $CURRENT_BRANCH"
else
  echo "branch: (detached)"
fi
echo "detached-head: $DETACHED_HEAD"
echo "base-is-ancestor: $BASE_IS_ANCESTOR"
echo "merge-base: $MERGE_BASE"
echo "worktree: $WORKTREE"
if [ "$WORKTREE" = "dirty" ]; then
  echo "worktree-files:"
  printf '%s\n' "$PORCELAIN" | sed 's/^/  /'
fi
echo "autofix-safe: $AUTOFIX_SAFE"
echo "autofix-reason: $AUTOFIX_REASON"
echo "review-range: $BASE_HASH..$HEAD_HASH"

echo "guidance-source: worktree"
echo "guidance:"
if [ -n "$GUIDANCE_FILES" ]; then
  printf '%s\n' "$GUIDANCE_FILES" | sed 's/^/  /'
else
  echo "  (none)"
fi

echo "changed-files:"
if git -C "$REPO_ROOT" diff --quiet "$BASE_HASH" "$HEAD_HASH" --; then
  echo "  (none)"
else
  git -C "$REPO_ROOT" diff --name-status "$BASE_HASH" "$HEAD_HASH" | sed 's/^/  /'
fi

echo "stat:"
stat_output="$(git -C "$REPO_ROOT" diff --stat "$BASE_HASH" "$HEAD_HASH")" \
  || die "git diff --stat failed for $BASE_HASH..$HEAD_HASH"
if [ -n "$stat_output" ]; then
  printf '%s\n' "$stat_output" | sed 's/^/  /'
else
  echo "  (none)"
fi

if [ "$HEAD_IS_CURRENT" = "yes" ]; then
  echo "next-round-range-policy: use $BASE_HASH..HEAD after a clean checkpoint commit"
else
  echo "next-round-range-policy: stop before editing unless user approves extending beyond $HEAD_HASH"
fi

if [ "$BASE_HASH" = "$EMPTY_TREE" ]; then
  echo "baseline-range: yes"
else
  echo "baseline-range: no"
fi
