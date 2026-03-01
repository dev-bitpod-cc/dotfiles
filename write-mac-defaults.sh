#!/usr/bin/env bash
#
# macOS 系統偏好設定腳本
# 版本：v1.0
#
# 使用方式：
#   chmod +x setup-mac-defaults.sh
#   ./setup-mac-defaults.sh
#
# 說明：
#   套用開發者常用的 macOS 系統偏好設定（defaults write）。
#   與開發工具環境安裝分開執行，避免混淆。
#

# 作業系統檢查
if [ "$(uname)" != "Darwin" ]; then
    echo "❌ 此腳本僅適用於 macOS"
    exit 1
fi

# 顏色定義
if [ -t 1 ] && command -v tput &> /dev/null && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    GREEN=''
    BLUE=''
    NC=''
fi

print_header() {
    echo -e "\n${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# ================================================
# macOS 系統偏好設定
# ================================================
print_header "macOS 系統偏好設定"

print_info "套用開發者常用系統設定..."

# Finder: 顯示副檔名
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
print_success "Finder: 顯示所有副檔名"

# Finder: 顯示路徑列
defaults write com.apple.finder ShowPathbar -bool true
print_success "Finder: 顯示路徑列"

# Finder: 顯示狀態列
defaults write com.apple.finder ShowStatusBar -bool true
print_success "Finder: 顯示狀態列"

# Dock: 放在右側
defaults write com.apple.dock orientation -string "right"
print_success "Dock: 放在螢幕右側"

# 鍵盤: 加快按鍵重複速度
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15
print_success "鍵盤: 加快按鍵重複速度"

# 觸控板: 輕點即點擊
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
print_success "觸控板: 輕點即點擊"

# 觸控板: 拖移鎖定（Drag Lock）
defaults write com.apple.AppleMultitouchTrackpad DragLock -bool true
defaults write com.apple.AppleMultitouchTrackpad Dragging -bool true
print_success "觸控板: 拖移鎖定"

# 捲軸: 永遠顯示
defaults write NSGlobalDomain AppleShowScrollBars -string "Always"
print_success "捲軸: 永遠顯示"

# 鎖定畫面/螢幕保護程式: 顯示時鐘
defaults write com.apple.screensaver showClock -bool true
print_success "螢幕保護程式: 顯示時鐘"

# 重新啟動受影響的應用程式
killall Finder 2>/dev/null || true
killall Dock 2>/dev/null || true
print_success "已重新啟動 Finder 和 Dock 以套用設定"

print_info "部分設定（鍵盤、觸控板）可能需要重新登入後才完全生效"

echo -e "\n${GREEN}✅ macOS 系統偏好設定完成！${NC}\n"
