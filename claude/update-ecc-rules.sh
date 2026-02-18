#!/usr/bin/env bash
#
# update-ecc-rules.sh — Sync ECC plugin rules to dotfiles
#
# Usage:
#   ./update-ecc-rules.sh                    # Sync default languages (typescript python golang)
#   ./update-ecc-rules.sh typescript python   # Sync specific languages
#   ./update-ecc-rules.sh --check            # Show diff without applying
#
# This script finds the latest installed Everything Claude Code plugin
# and copies its rules to ~/.dotfiles/claude/rules/ (which should be
# symlinked from ~/.claude/rules/).
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="$SCRIPT_DIR/rules"
ECC_CACHE_DIR="$HOME/.claude/plugins/cache/everything-claude-code/everything-claude-code"
DEFAULT_LANGS=(typescript python golang)
CHECK_ONLY=false

# --- Colors ---
if [ -t 1 ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    RED='\033[0;31m'
    NC='\033[0m'
else
    GREEN='' YELLOW='' BLUE='' RED='' NC=''
fi

# --- Parse args ---
LANGS=()
for arg in "$@"; do
    case "$arg" in
        --check) CHECK_ONLY=true ;;
        --help|-h)
            echo "Usage: $0 [--check] [language ...]"
            echo "  --check   Show diff without applying"
            echo "  Default languages: ${DEFAULT_LANGS[*]}"
            exit 0
            ;;
        *) LANGS+=("$arg") ;;
    esac
done

[ ${#LANGS[@]} -eq 0 ] && LANGS=("${DEFAULT_LANGS[@]}")

# --- Find latest ECC version ---
if [ ! -d "$ECC_CACHE_DIR" ]; then
    echo -e "${RED}ECC plugin not found at $ECC_CACHE_DIR${NC}" >&2
    echo "Install it first: /plugin install everything-claude-code@everything-claude-code" >&2
    exit 1
fi

# Sort versions and pick the latest
LATEST_VERSION=$(ls -1 "$ECC_CACHE_DIR" | sort -V | tail -1)
ECC_RULES_DIR="$ECC_CACHE_DIR/$LATEST_VERSION/rules"

if [ ! -d "$ECC_RULES_DIR" ]; then
    echo -e "${RED}Rules directory not found: $ECC_RULES_DIR${NC}" >&2
    exit 1
fi

echo -e "${BLUE}ECC version: $LATEST_VERSION${NC}"
echo -e "${BLUE}Source:      $ECC_RULES_DIR${NC}"
echo -e "${BLUE}Destination: $DEST_DIR${NC}"
echo -e "${BLUE}Languages:   ${LANGS[*]}${NC}"
echo ""

# --- Show diff ---
has_changes=false

show_diff() {
    local dir_name="$1"
    local src="$ECC_RULES_DIR/$dir_name"
    local dst="$DEST_DIR/$dir_name"

    if [ ! -d "$src" ]; then
        echo -e "${YELLOW}Warning: $src does not exist, skipping${NC}" >&2
        return
    fi

    if [ ! -d "$dst" ]; then
        echo -e "${GREEN}+ New: $dir_name/ ($(ls -1 "$src" | wc -l | tr -d ' ') files)${NC}"
        has_changes=true
        return
    fi

    local diff_output
    diff_output=$(diff -rq "$src" "$dst" 2>/dev/null || true)
    if [ -n "$diff_output" ]; then
        echo -e "${YELLOW}~ Changed: $dir_name/${NC}"
        echo "$diff_output" | sed 's/^/  /'
        has_changes=true
    else
        echo -e "  No changes: $dir_name/"
    fi
}

show_diff "common"
for lang in "${LANGS[@]}"; do
    show_diff "$lang"
done

# Check README.md
if [ -f "$ECC_RULES_DIR/README.md" ]; then
    if [ ! -f "$DEST_DIR/README.md" ] || ! diff -q "$ECC_RULES_DIR/README.md" "$DEST_DIR/README.md" &>/dev/null; then
        echo -e "${YELLOW}~ Changed: README.md${NC}"
        has_changes=true
    fi
fi

echo ""

if [ "$CHECK_ONLY" = true ]; then
    if [ "$has_changes" = true ]; then
        echo -e "${YELLOW}Changes detected. Run without --check to apply.${NC}"
    else
        echo -e "${GREEN}Already up to date.${NC}"
    fi
    exit 0
fi

if [ "$has_changes" = false ]; then
    echo -e "${GREEN}Already up to date. Nothing to sync.${NC}"
    exit 0
fi

# --- Apply ---
echo -e "${BLUE}Syncing rules...${NC}"

mkdir -p "$DEST_DIR"

# common (always)
echo "  Syncing common/"
mkdir -p "$DEST_DIR/common"
cp -r "$ECC_RULES_DIR/common/." "$DEST_DIR/common/"

# Languages
for lang in "${LANGS[@]}"; do
    if [ -d "$ECC_RULES_DIR/$lang" ]; then
        echo "  Syncing $lang/"
        mkdir -p "$DEST_DIR/$lang"
        cp -r "$ECC_RULES_DIR/$lang/." "$DEST_DIR/$lang/"
    else
        echo -e "  ${YELLOW}Skipping $lang/ (not found in ECC)${NC}"
    fi
done

# README.md
if [ -f "$ECC_RULES_DIR/README.md" ]; then
    cp "$ECC_RULES_DIR/README.md" "$DEST_DIR/README.md"
fi

echo ""
echo -e "${GREEN}Done. Rules synced from ECC v$LATEST_VERSION.${NC}"
echo -e "Remember to commit changes in ~/.dotfiles/ if needed."
