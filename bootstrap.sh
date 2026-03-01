#!/usr/bin/env bash
#
# macOS 開發環境 Bootstrap 腳本
#
# 新 Mac 上只需執行這一行：
#   curl -fsSL dot.bitpod.cc | sh
#
# 此腳本會依序：
#   1. 安裝 Xcode Command Line Tools（取得 git）
#   2. Clone dotfiles repo 至 ~/.dotfiles
#   3. 執行 setup-mac-env.sh
#

set -e

# 顏色定義
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    RED='\033[0;31m'
    NC='\033[0m'
else
    GREEN='' YELLOW='' BLUE='' RED='' NC=''
fi

print_step()    { echo -e "\n${BLUE}▶ $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error()   { echo -e "${RED}❌ $1${NC}"; }

DOTFILES_REPO="https://github.com/dev-bitpod-cc/dotfiles.git"
DOTFILES_DIR="$HOME/.dotfiles"

# 作業系統檢查
if [ "$(uname)" != "Darwin" ]; then
    print_error "此腳本僅適用於 macOS"
    exit 1
fi

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  macOS 開發環境 Bootstrap${NC}"
echo -e "${BLUE}================================================${NC}"

# ------------------------------------------------
# 步驟 1: Xcode Command Line Tools
# ------------------------------------------------
print_step "步驟 1/3: 檢查 Xcode Command Line Tools"

if xcode-select -p &> /dev/null; then
    print_success "Xcode Command Line Tools 已安裝"
else
    print_warning "Xcode Command Line Tools 未安裝，開始安裝..."
    xcode-select --install

    echo ""
    echo "請在彈出的視窗中點擊「安裝」，完成後按 Enter 繼續..."
    read -r

    # 驗證安裝
    if ! xcode-select -p &> /dev/null; then
        print_error "Xcode Command Line Tools 安裝失敗，請手動安裝後重新執行此腳本"
        exit 1
    fi
    print_success "Xcode Command Line Tools 安裝完成"
fi

# ------------------------------------------------
# 步驟 2: Clone dotfiles
# ------------------------------------------------
print_step "步驟 2/3: Clone dotfiles repo"

if [ -d "$DOTFILES_DIR" ]; then
    print_warning "$DOTFILES_DIR 已存在，執行 git pull..."
    git -C "$DOTFILES_DIR" pull
    print_success "dotfiles 已更新"
else
    git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
    print_success "dotfiles 已 clone 至 $DOTFILES_DIR"
fi

# ------------------------------------------------
# 步驟 3: 執行 setup-mac-env.sh
# ------------------------------------------------
print_step "步驟 3/3: 執行環境安裝腳本"

chmod +x "$DOTFILES_DIR/setup-mac-env.sh"
exec "$DOTFILES_DIR/setup-mac-env.sh"
