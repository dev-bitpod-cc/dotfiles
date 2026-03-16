#!/bin/bash
#
# Ubuntu 24.04 現代化開發環境自動安裝腳本
# 版本：v3.1
# 最後更新：2026-01-12
#
# 使用方式：
#   chmod +x setup-linux-env.sh
#   ./setup-linux-env.sh
#   ./setup-linux-env.sh -y    # 跳過確認提示
#
# 特色：
#   - 智能 PATH 統合（保留現有設定、去重、依慣例排序）
#   - 所有配置集中在 .bashrc（Linux 圖形終端預設只讀 .bashrc）
#   - 保留 conda、nvm 等重要初始化代碼
#

set -e  # 遇到錯誤立即退出

# 解析參數
AUTO_YES=false
while getopts "y" opt; do
    case $opt in
        y) AUTO_YES=true ;;
        *) echo "用法: $0 [-y]"; exit 1 ;;
    esac
done

# ================================================
# 顏色定義
# ================================================
if [ -t 1 ] && command -v tput &> /dev/null && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    NC=''
fi

# ================================================
# 輔助函數
# ================================================
print_header() {
    echo -e "\n${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# ================================================
# 提取使用者自訂設定到 .local 檔案
# ================================================
extract_user_settings() {
    print_info "檢查使用者自訂設定..."

    # .bashrc.local - 如果不存在才建立
    if [ ! -f ~/.bashrc.local ]; then
        cat > ~/.bashrc.local << 'LOCAL_EOF'
# ===========================================
# 使用者自訂設定
# ===========================================
# 此檔案不會被 setup-linux-env.sh 覆寫
# 請在此添加您的個人別名、函數和環境變數
#
# 範例：
#   alias myproj='cd ~/MyProject'
#   export MY_VAR="value"
#
LOCAL_EOF

        # 從現有 .bashrc 提取自訂設定
        if [ -f ~/.bashrc ]; then
            echo "" >> ~/.bashrc.local
            echo "# --- 從原有 .bashrc 提取 ($(date +%Y-%m-%d)) ---" >> ~/.bashrc.local

            # 提取自訂 alias（排除腳本預設的）
            grep -E "^alias " ~/.bashrc 2>/dev/null | \
                grep -v "ll=\|la=\|lt=\|llt=\|gs=\|gd=\|ga=\|gc=\|gp=\|gl=\|gco=\|gb=\|glog=\|gdd=\|sysup=\|fd=\|bat=" \
                >> ~/.bashrc.local || true

            # 提取自訂 export（排除腳本預設的）
            grep -E "^export " ~/.bashrc 2>/dev/null | \
                grep -v "PATH=\|FZF_\|BAT_\|CLICOLOR\|NVM_DIR" \
                >> ~/.bashrc.local || true
        fi
        print_success "已建立 .bashrc.local"
    else
        print_info ".bashrc.local 已存在，保留使用者設定"
    fi

    # .bash_profile.local - 如果不存在才建立
    if [ ! -f ~/.bash_profile.local ]; then
        cat > ~/.bash_profile.local << 'LOCAL_EOF'
# ===========================================
# 使用者自訂 PATH 和環境設定
# ===========================================
# 此檔案不會被 setup-linux-env.sh 覆寫
# 請在此添加您的個人 PATH 設定
#
# 範例：
#   export PATH="$HOME/my-tools/bin:$PATH"
#
LOCAL_EOF

        # 從現有 .bash_profile 提取自訂 PATH
        if [ -f ~/.bash_profile ]; then
            echo "" >> ~/.bash_profile.local
            echo "# --- 從原有 .bash_profile 提取 ($(date +%Y-%m-%d)) ---" >> ~/.bash_profile.local

            grep -E "^export PATH=|^PATH=" ~/.bash_profile 2>/dev/null | \
                grep -v "\.local/bin\|\.bun/bin\|\.cargo/bin\|go/bin\|\.npm-global" \
                >> ~/.bash_profile.local || true
        fi
        print_success "已建立 .bash_profile.local"
    else
        print_info ".bash_profile.local 已存在，保留使用者設定"
    fi
}

# 生成 PATH 設定代碼
# 策略：
#   1. 按優先級從低到高添加路徑（最高優先級最後添加，排在最前面）
#   2. 最後執行去重函數，移除重複路徑並保持順序
generate_path_config() {
    cat << 'PATH_CONFIG_EOF'
# -------------------------------------------
# PATH 設定（按優先級排序，高優先級在前）
# -------------------------------------------

# PATH 去重函數：移除重複路徑，保留第一次出現的位置
# 支援正規化：~ → $HOME，移除尾部斜線
__dedupe_path() {
    local new_path=""
    local seen_paths=""
    local IFS=':'

    for dir in $PATH; do
        # 跳過空路徑
        [ -z "$dir" ] && continue

        # 正規化路徑：展開 ~ 為 $HOME，移除尾部斜線
        local normalized="$dir"
        case "$normalized" in
            "~/"*) normalized="$HOME/${normalized#\~/}" ;;
            "~")   normalized="$HOME" ;;
        esac
        normalized="${normalized%/}"

        # 檢查正規化後的路徑是否已存在
        case ":$seen_paths:" in
            *":$normalized:"*) ;;  # 已存在，跳過
            *)
                seen_paths="${seen_paths:+$seen_paths:}$normalized"
                new_path="${new_path:+$new_path:}$normalized"
                ;;
        esac
    done
    export PATH="$new_path"
}

# 按優先級從低到高添加（最後添加的排在最前面）

# 優先級 5: Go
[ -d "$HOME/go/bin" ] && export PATH="$HOME/go/bin:$PATH"

# 優先級 4: Cargo (Rust)
if [ -f "$HOME/.cargo/env" ]; then
    source "$HOME/.cargo/env"
elif [ -d "$HOME/.cargo/bin" ]; then
    export PATH="$HOME/.cargo/bin:$PATH"
fi

# 優先級 3: Bun
[ -d "$HOME/.bun/bin" ] && export PATH="$HOME/.bun/bin:$PATH"

# npm 全域套件（相容性備用，優先級低於 bun）
[ -d "$HOME/.npm-global/bin" ] && export PATH="$HOME/.npm-global/bin:$PATH"

# 優先級 1: 用戶本地程式（最高優先級）
[ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH"

# 執行去重，移除重複路徑
__dedupe_path

PATH_CONFIG_EOF
}

# ================================================
# 主程式開始
# ================================================

# 檢查是否為 root
if [ "$EUID" -eq 0 ]; then
    print_error "請不要使用 root 執行此腳本"
    exit 1
fi

# 檢查是否為 Linux
if [ "$(uname)" != "Linux" ]; then
    print_error "此腳本僅適用於 Linux"
    exit 1
fi

# 檢查是否為 Ubuntu
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" != "ubuntu" ]; then
        print_warning "此腳本專為 Ubuntu 設計，當前系統：$PRETTY_NAME"
        if [ "$AUTO_YES" = false ]; then
            echo -n "是否繼續？[y/N] "
            read -r response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                exit 0
            fi
        fi
    fi
fi

print_header "Ubuntu 現代化開發環境自動安裝 v3.1"
echo "此腳本將："
echo "  • 安裝 29+ 個開發工具"
echo "  • 智能統合現有 PATH 設定（去重、排序）"
echo "  • 保留 conda、nvm 等重要配置"
echo "  • 所有配置集中在 .bashrc"
echo "  • 預估時間：3-6 分鐘"
echo ""
print_warning "現有的 .bashrc 和 .bash_profile 將被備份"
echo ""
if [ "$AUTO_YES" = false ]; then
    echo -n "確定要繼續嗎？[Y/n] "
    read -r response
    if [[ "$response" =~ ^[Nn]$ ]]; then
        print_info "已取消"
        exit 0
    fi
fi

# ================================================
# 步驟 0：系統準備
# ================================================
print_header "步驟 0: 系統準備"

print_info "檢查系統資訊..."
echo "OS: $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')"
echo "Kernel: $(uname -r)"
echo "Architecture: $(uname -m)"

print_info "更新套件清單..."
sudo apt update -qq

print_info "確保 zh_TW.UTF-8 locale 可用..."
if ! locale -a 2>/dev/null | grep -q zh_TW; then
    sudo locale-gen zh_TW.UTF-8 >/dev/null 2>&1
    print_success "zh_TW.UTF-8 locale 已產生"
else
    print_info "zh_TW.UTF-8 locale 已存在"
fi

print_info "安裝基本編譯工具..."
sudo apt install -y -qq \
    build-essential \
    curl \
    wget \
    git \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    >/dev/null 2>&1

print_success "系統準備完成"

# ================================================
# 步驟 1: 安裝開發工具
# ================================================
print_header "步驟 1: 安裝開發工具"

# 1.1 安裝核心工具
print_info "安裝核心工具..."
sudo apt install -y -qq \
    git \
    wget \
    curl \
    htop \
    tree \
    tmux \
    jq \
    python3 \
    python-is-python3 \
    unzip \
    zip \
    >/dev/null 2>&1

print_success "核心工具安裝完成"

# 1.1.1 安裝 uv（Python 套件管理，優先於 pip）
if command -v uv &> /dev/null; then
    print_info "uv 已安裝 ($(uv --version))"
else
    print_info "安裝 uv..."
    if curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1; then
        export PATH="$HOME/.local/bin:$PATH"
        print_success "uv 安裝完成 ($(uv --version 2>/dev/null || echo 'installed'))"
    else
        print_warning "uv 安裝失敗，已跳過"
    fi
fi

# 1.2 安裝 Node.js
if command -v node &> /dev/null; then
    print_info "Node.js 已安裝 ($(node --version))"
else
    print_info "安裝 Node.js 22.x LTS..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - >/dev/null 2>&1
    sudo apt install -y nodejs >/dev/null 2>&1
    print_success "Node.js 安裝完成 ($(node --version))"
fi

# 1.2.1 安裝 Bun（主要 JS runtime）
if command -v bun &> /dev/null; then
    print_info "Bun 已安裝 ($(bun --version))"
else
    print_info "安裝 Bun..."
    if curl -fsSL https://bun.sh/install | bash >/dev/null 2>&1; then
        export PATH="$HOME/.bun/bin:$PATH"
        print_success "Bun 安裝完成 ($(~/.bun/bin/bun --version 2>/dev/null || echo 'installed'))"
    else
        print_warning "Bun 安裝失敗，已跳過"
    fi
fi

# 1.3 安裝 GitHub CLI
if command -v gh &> /dev/null; then
    print_info "GitHub CLI 已安裝"
else
    print_info "安裝 GitHub CLI..."
    sudo mkdir -p -m 755 /etc/apt/keyrings
    wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
        sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
    sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg

    ARCH=$(dpkg --print-architecture)
    echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
        sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null

    sudo apt update -qq
    sudo apt install -y gh >/dev/null 2>&1
    print_success "GitHub CLI 安裝完成"
fi

# 1.4 安裝現代化 CLI 工具（apt）
print_info "安裝現代化 CLI 工具..."
sudo apt install -y -qq \
    ripgrep \
    fd-find \
    bat \
    fzf \
    shellcheck \
    >/dev/null 2>&1

print_success "apt 工具安裝完成"

# 1.4.1 安裝 httpie（透過 uv）
if command -v http &> /dev/null; then
    print_info "httpie 已安裝"
else
    print_info "安裝 httpie..."
    if uv tool install httpie >/dev/null 2>&1; then
        print_success "httpie 安裝完成"
    else
        print_warning "httpie 安裝失敗，已跳過"
    fi
fi

# 1.5 安裝 eza
if command -v eza &> /dev/null; then
    print_info "eza 已安裝"
else
    print_info "安裝 eza..."
    sudo mkdir -p /etc/apt/keyrings
    wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | \
        sudo gpg --dearmor --yes -o /etc/apt/keyrings/gierens.gpg 2>/dev/null
    echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | \
        sudo tee /etc/apt/sources.list.d/gierens.list > /dev/null
    sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
    sudo apt update -qq
    sudo apt install -y eza >/dev/null 2>&1
    print_success "eza 安裝完成"
fi

# 1.6 安裝 zoxide
if command -v zoxide &> /dev/null; then
    print_info "zoxide 已安裝"
else
    print_info "安裝 zoxide..."
    curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh >/dev/null 2>&1
    print_success "zoxide 安裝完成"
fi

# 1.7 安裝 git-delta
if command -v delta &> /dev/null; then
    print_info "git-delta 已安裝"
else
    print_info "安裝 git-delta..."
    DELTA_VERSION=$(curl -s "https://api.github.com/repos/dandavison/delta/releases/latest" | grep -Po '"tag_name": "\K[^"]*' || echo "0.18.2")

    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        DELTA_ARCH="amd64"
    elif [ "$ARCH" = "aarch64" ]; then
        DELTA_ARCH="arm64"
    else
        print_warning "不支援的架構: $ARCH，跳過 git-delta"
        DELTA_ARCH=""
    fi

    if [ -n "$DELTA_ARCH" ]; then
        if wget -q "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/git-delta_${DELTA_VERSION}_${DELTA_ARCH}.deb" -O /tmp/delta.deb; then
            sudo dpkg -i /tmp/delta.deb >/dev/null 2>&1 || true
            rm -f /tmp/delta.deb
            print_success "git-delta 安裝完成"
        else
            print_warning "git-delta 下載失敗，已跳過"
            rm -f /tmp/delta.deb
        fi
    fi
fi

# 1.8 安裝 yq
if command -v yq &> /dev/null; then
    print_info "yq 已安裝"
else
    print_info "安裝 yq..."
    ARCH=$(dpkg --print-architecture)
    sudo wget -q "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${ARCH}" -O /usr/local/bin/yq
    sudo chmod +x /usr/local/bin/yq
    print_success "yq 安裝完成"
fi

# 1.9 安裝 tldr
if command -v tldr &> /dev/null; then
    print_info "tldr 已安裝"
else
    print_info "安裝 tldr..."
    bun install -g tldr >/dev/null 2>&1
    print_success "tldr 安裝完成"
fi

# 1.10 安裝 lazygit
if command -v lazygit &> /dev/null; then
    print_info "lazygit 已安裝"
else
    print_info "安裝 lazygit..."
    LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*' || echo "0.44.1")
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        LAZYGIT_ARCH="x86_64"
    elif [ "$ARCH" = "aarch64" ]; then
        LAZYGIT_ARCH="arm64"
    else
        print_warning "不支援的架構: $ARCH，跳過 lazygit"
        LAZYGIT_ARCH=""
    fi

    if [ -n "$LAZYGIT_ARCH" ]; then
        if curl -fLo /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_${LAZYGIT_ARCH}.tar.gz" 2>/dev/null; then
            tar xf /tmp/lazygit.tar.gz -C /tmp lazygit
            sudo install /tmp/lazygit /usr/local/bin
            rm /tmp/lazygit.tar.gz /tmp/lazygit
            print_success "lazygit 安裝完成"
        else
            print_warning "lazygit 下載失敗，已跳過"
        fi
    fi
fi

# 1.11 安裝 dust（磁碟空間分析）
if command -v dust &> /dev/null; then
    print_info "dust 已安裝"
else
    print_info "安裝 dust..."
    DUST_VERSION=$(curl -s "https://api.github.com/repos/bootandy/dust/releases/latest" | grep -Po '"tag_name": "v\K[^"]*' || echo "1.1.1")
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        DUST_ARCH="x86_64-unknown-linux-gnu"
    elif [ "$ARCH" = "aarch64" ]; then
        DUST_ARCH="aarch64-unknown-linux-gnu"
    else
        print_warning "不支援的架構: $ARCH，跳過 dust"
        DUST_ARCH=""
    fi

    if [ -n "$DUST_ARCH" ]; then
        if curl -fLo /tmp/dust.tar.gz "https://github.com/bootandy/dust/releases/download/v${DUST_VERSION}/dust-v${DUST_VERSION}-${DUST_ARCH}.tar.gz" 2>/dev/null; then
            tar xf /tmp/dust.tar.gz -C /tmp
            sudo install /tmp/dust-v${DUST_VERSION}-${DUST_ARCH}/dust /usr/local/bin
            rm -rf /tmp/dust.tar.gz /tmp/dust-v${DUST_VERSION}-${DUST_ARCH}
            print_success "dust 安裝完成"
        else
            print_warning "dust 下載失敗，已跳過"
        fi
    fi
fi

# 1.12 安裝 duf（磁碟使用量顯示）
if command -v duf &> /dev/null; then
    print_info "duf 已安裝"
else
    print_info "安裝 duf..."
    DUF_VERSION=$(curl -s "https://api.github.com/repos/muesli/duf/releases/latest" | grep -Po '"tag_name": "v\K[^"]*' || echo "0.8.1")
    ARCH=$(dpkg --print-architecture)
    if curl -fLo /tmp/duf.deb "https://github.com/muesli/duf/releases/download/v${DUF_VERSION}/duf_${DUF_VERSION}_linux_${ARCH}.deb" 2>/dev/null; then
        sudo dpkg -i /tmp/duf.deb >/dev/null 2>&1 || true
        rm -f /tmp/duf.deb
        print_success "duf 安裝完成"
    else
        print_warning "duf 下載失敗，已跳過"
        rm -f /tmp/duf.deb
    fi
fi

# 1.13 安裝 tokei（程式碼統計）
if command -v tokei &> /dev/null; then
    print_info "tokei 已安裝"
else
    print_info "安裝 tokei..."
    TOKEI_VERSION=$(curl -s "https://api.github.com/repos/XAMPPRocky/tokei/releases" | grep -Po '"tag_name": "v\K[^"]*' | while read -r ver; do
        ASSETS=$(curl -s "https://api.github.com/repos/XAMPPRocky/tokei/releases/tags/v${ver}" | grep -c '"browser_download_url"' || true)
        if [ "$ASSETS" -gt 0 ]; then echo "$ver"; break; fi
    done)
    TOKEI_VERSION="${TOKEI_VERSION:-12.1.2}"
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        TOKEI_ARCH="x86_64-unknown-linux-gnu"
    elif [ "$ARCH" = "aarch64" ]; then
        TOKEI_ARCH="aarch64-unknown-linux-gnu"
    else
        TOKEI_ARCH=""
    fi
    if [ -n "$TOKEI_ARCH" ]; then
        if curl -fLo /tmp/tokei.tar.gz "https://github.com/XAMPPRocky/tokei/releases/download/v${TOKEI_VERSION}/tokei-${TOKEI_ARCH}.tar.gz" 2>/dev/null; then
            tar xf /tmp/tokei.tar.gz -C /tmp tokei
            sudo install /tmp/tokei /usr/local/bin
            rm -f /tmp/tokei.tar.gz /tmp/tokei
            print_success "tokei 安裝完成"
        else
            print_warning "tokei 下載失敗，已跳過"
        fi
    fi
fi

# 1.14 安裝 sd（搜尋替換）
if command -v sd &> /dev/null; then
    print_info "sd 已安裝"
else
    print_info "安裝 sd..."
    SD_VERSION=$(curl -s "https://api.github.com/repos/chmln/sd/releases/latest" | grep -Po '"tag_name": "v\K[^"]*' || echo "1.0.0")
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        SD_ARCH="x86_64-unknown-linux-gnu"
    elif [ "$ARCH" = "aarch64" ]; then
        SD_ARCH="aarch64-unknown-linux-gnu"
    else
        SD_ARCH=""
    fi
    if [ -n "$SD_ARCH" ]; then
        if curl -fLo /tmp/sd.tar.gz "https://github.com/chmln/sd/releases/download/v${SD_VERSION}/sd-v${SD_VERSION}-${SD_ARCH}.tar.gz" 2>/dev/null; then
            tar xf /tmp/sd.tar.gz -C /tmp
            sudo install /tmp/sd-v${SD_VERSION}-${SD_ARCH}/sd /usr/local/bin
            rm -rf /tmp/sd.tar.gz /tmp/sd-v${SD_VERSION}-${SD_ARCH}
            print_success "sd 安裝完成"
        else
            print_warning "sd 下載失敗，已跳過"
        fi
    fi
fi

# 1.15 安裝 hyperfine（效能測試）
if command -v hyperfine &> /dev/null; then
    print_info "hyperfine 已安裝"
else
    print_info "安裝 hyperfine..."
    HYPERFINE_VERSION=$(curl -s "https://api.github.com/repos/sharkdp/hyperfine/releases/latest" | grep -Po '"tag_name": "v\K[^"]*' || echo "1.19.0")
    ARCH=$(dpkg --print-architecture)
    if curl -fLo /tmp/hyperfine.deb "https://github.com/sharkdp/hyperfine/releases/download/v${HYPERFINE_VERSION}/hyperfine_${HYPERFINE_VERSION}_${ARCH}.deb" 2>/dev/null; then
        sudo dpkg -i /tmp/hyperfine.deb >/dev/null 2>&1 || true
        rm -f /tmp/hyperfine.deb
        print_success "hyperfine 安裝完成"
    else
        print_warning "hyperfine 下載失敗，已跳過"
        rm -f /tmp/hyperfine.deb
    fi
fi

# ================================================
# 步驟 2: 建立配置檔案
# ================================================
print_header "步驟 2: 建立配置檔案"

# 備份現有配置
BACKUP_SUFFIX=$(date +%Y%m%d_%H%M%S)

if [ -f ~/.bashrc ]; then
    cp ~/.bashrc ~/.bashrc.backup.$BACKUP_SUFFIX
    print_success "已備份 .bashrc → .bashrc.backup.$BACKUP_SUFFIX"
fi

if [ -f ~/.bash_profile ]; then
    cp ~/.bash_profile ~/.bash_profile.backup.$BACKUP_SUFFIX
    print_success "已備份 .bash_profile → .bash_profile.backup.$BACKUP_SUFFIX"
fi

# 檢測並保存重要的初始化代碼
print_info "分析現有配置..."

CONDA_INIT=""
NVM_INIT=""
EXISTING_PATH_CONFIG=""

if [ -f ~/.bashrc ]; then
    # 提取 conda 初始化
    if grep -q "conda initialize" ~/.bashrc; then
        CONDA_INIT=$(sed -n '/>>> conda initialize >>>/,/<<< conda initialize <<</p' ~/.bashrc)
        print_info "檢測到 conda 配置，將會保留"
    fi
fi

# 檢測 nvm
if [ -d ~/.nvm ]; then
    print_info "檢測到 nvm，將會保留配置"
fi

# 提取使用者自訂設定到 .local 檔案
extract_user_settings

# 統合 PATH
print_info "統合 PATH 設定..."
EXISTING_PATH_CONFIG=$(generate_path_config)
print_success "PATH 統合完成"

# 顯示將要設定的 PATH 順序（優先級從高到低）
echo ""
echo -e "${CYAN}PATH 優先級順序（高到低）：${NC}"
echo "  [1] \$HOME/.local/bin        # 用戶本地程式（uv 等）"
echo "  [2] \$HOME/.bun/bin          # Bun"
echo "  [3] \$HOME/.cargo/bin        # Cargo (Rust)"
echo "  [4] \$HOME/go/bin            # Go"
echo "  [5] (conda 路徑)             # 由 conda init 管理"
echo "  [6] /usr/local/bin 等        # 系統路徑"
echo ""

# 建立 .bash_profile（極簡版，只載入 .bashrc）
print_info "建立 .bash_profile..."
cat > ~/.bash_profile << 'EOF'
# ===========================================
# 登入 Shell 配置（Linux）
# ===========================================
#
# 所有配置已集中在 .bashrc
# 此檔案僅確保登入 shell 也能載入 .bashrc
#
# ===========================================

# 載入 .bashrc
if [ -f ~/.bashrc ]; then
    source ~/.bashrc
fi
EOF

print_success ".bash_profile 已建立（極簡版）"

# 建立 .bashrc
print_info "建立 .bashrc..."
cat > ~/.bashrc << 'BASHRC_EOF'
# ===========================================
# 現代化開發環境配置（Linux）
# ===========================================
# 版本：v3.1
# 最後更新：2026-01-12
# 自動生成於：Ubuntu 環境設定腳本
#
# 策略：
#   - 所有配置集中在此檔案
#   - PATH 已統合並依慣例排序
#   - 保留原生命令（ls, cat, find, grep）
#   - 現代化工具用原名（eza, bat, fd, rg）
# ===========================================

# 非互動式 shell 直接返回
case $- in
    *i*) ;;
      *) return;;
esac

BASHRC_EOF

# 插入統合後的 PATH 設定
echo "$EXISTING_PATH_CONFIG" >> ~/.bashrc

# 繼續寫入其餘配置
cat >> ~/.bashrc << 'BASHRC_EOF'

# -------------------------------------------
# 工具初始化
# -------------------------------------------

# fzf 快捷鍵
if [ -f /usr/share/doc/fzf/examples/key-bindings.bash ]; then
    source /usr/share/doc/fzf/examples/key-bindings.bash
fi
if [ -f /usr/share/doc/fzf/examples/completion.bash ]; then
    source /usr/share/doc/fzf/examples/completion.bash
fi

# zoxide（智能目錄跳轉）
if command -v zoxide &> /dev/null; then
    eval "$(zoxide init bash)"
fi

# -------------------------------------------
# 環境變數
# -------------------------------------------

# 從 .env 載入 API Keys（如果存在）
if [ -f ~/.env ]; then
    set -a
    source ~/.env
    set +a
fi

# -------------------------------------------
# Ubuntu 命令別名修正
# -------------------------------------------

# Ubuntu 中 fd 叫 fdfind，bat 叫 batcat
if command -v fdfind &> /dev/null && ! command -v fd &> /dev/null; then
    alias fd='fdfind'
fi

if command -v batcat &> /dev/null && ! command -v bat &> /dev/null; then
    alias bat='batcat'
fi

# -------------------------------------------
# 便捷別名
# -------------------------------------------

# eza 別名（如果已安裝）
if command -v eza &> /dev/null; then
    alias ll='eza -l'
    alias la='eza -la'
    alias lt='eza --tree'
    alias llt='eza -l --tree'
fi

# 啟用顏色
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'

# Git 別名
alias gs='git status'
alias gd='git diff'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git pull'
alias gco='git checkout'
alias gb='git branch'
alias glog='git log --oneline --graph --decorate'

# Claude Code
alias clauded='claude --dangerously-skip-permissions'
alias claudea='claude --enable-auto-mode'

# 系統更新
alias sysup='(cd ~/.dotfiles && git pull 2>/dev/null); sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y; { command -v claude &>/dev/null && claude plugins marketplace update 2>/dev/null; jq -r ".enabledPlugins // {} | keys[]" ~/.dotfiles/claude/settings.json 2>/dev/null | while read -r p; do claude plugins install "$p" 2>/dev/null; claude plugins update "$p" 2>/dev/null; done; } 2>/dev/null'

# NVIDIA GPU 工具（僅在有 GPU 時載入）
if command -v nvidia-smi &>/dev/null; then
    nvidia-check() {
        echo "Currently held packages:"
        sudo apt-mark showhold | grep -iE 'nvidia|cuda|libnvidia'
        echo ""
        echo "Available updates:"
        sudo apt update -qq 2>/dev/null
        sudo apt list --upgradable 2>/dev/null | grep -iE 'nvidia|cuda|libnvidia'
        echo ""
        echo "To upgrade, run in Claude Code for guided execution."
    }
    nvidia-hold() {
        local pkgs
        pkgs=$(dpkg -l | awk '/^ii.*(nvidia|cuda|libnvidia)/{print $2}')
        if [ -z "$pkgs" ]; then
            echo "No NVIDIA/CUDA packages found."
            return 1
        fi
        echo "Will hold the following packages:"
        echo "$pkgs"
        echo ""
        read -p "Proceed? [y/N] " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Cancelled."; return 0; }
        echo "$pkgs" | xargs sudo apt-mark hold
        echo ""
        echo "Done. These packages will not be upgraded by sysup."
    }
fi

# -------------------------------------------
# fzf 配置
# -------------------------------------------

if command -v fzf &> /dev/null; then
    export FZF_DEFAULT_OPTS='
      --height 40%
      --layout=reverse
      --border
      --preview "bat --color=always --style=numbers --line-range :500 {} 2>/dev/null || batcat --color=always --style=numbers --line-range :500 {} 2>/dev/null || cat {}"
      --preview-window=right:50%
    '

    if command -v fd &> /dev/null; then
        export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
        export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
        export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
    elif command -v fdfind &> /dev/null; then
        export FZF_DEFAULT_COMMAND='fdfind --type f --hidden --follow --exclude .git'
        export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
        export FZF_ALT_C_COMMAND='fdfind --type d --hidden --follow --exclude .git'
    fi

    if command -v eza &> /dev/null; then
        export FZF_ALT_C_OPTS="--preview 'eza --tree --level=2 --color=always {}'"
    elif command -v tree &> /dev/null; then
        export FZF_ALT_C_OPTS="--preview 'tree -C {} | head -200'"
    fi
fi

# -------------------------------------------
# bat 配置
# -------------------------------------------

if command -v bat &> /dev/null || command -v batcat &> /dev/null; then
    export BAT_THEME="TwoDark"
    export BAT_PAGER="less -RF"
fi

# -------------------------------------------
# 其他設定
# -------------------------------------------

export CLICOLOR=1
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export EDITOR=vim
HISTSIZE=50000
HISTFILESIZE=50000
HISTCONTROL=ignoredups:erasedups
shopt -s histappend

# -------------------------------------------
# 自訂函數
# -------------------------------------------

# 用 fzf 搜尋並編輯檔案
if command -v fzf &> /dev/null; then
    fe() {
        local file
        local fd_cmd=$(command -v fd || command -v fdfind)
        local bat_cmd=$(command -v bat || command -v batcat)

        if [ -n "$fd_cmd" ] && [ -n "$bat_cmd" ]; then
            file=$($fd_cmd --type f --hidden --follow --exclude .git | fzf --preview "$bat_cmd --color=always --style=numbers {}")
        elif [ -n "$fd_cmd" ]; then
            file=$($fd_cmd --type f --hidden --follow --exclude .git | fzf)
        else
            file=$(find . -type f 2>/dev/null | fzf)
        fi

        [ -n "$file" ] && ${EDITOR:-vim} "$file"
    }

    # 快速切換專案目錄
    proj() {
        local dir
        local fd_cmd=$(command -v fd || command -v fdfind)

        if [ -d ~/Projects ]; then
            if [ -n "$fd_cmd" ]; then
                dir=$($fd_cmd --type d --max-depth 3 . ~/Projects | fzf --preview 'eza --tree --level=2 {} 2>/dev/null || tree -C {} | head -200')
            else
                dir=$(find ~/Projects -maxdepth 3 -type d 2>/dev/null | fzf)
            fi
        else
            if [ -n "$fd_cmd" ]; then
                dir=$($fd_cmd --type d --max-depth 3 . ~ | fzf --preview 'eza --tree --level=2 {} 2>/dev/null || tree -C {} | head -200')
            else
                dir=$(find ~ -maxdepth 3 -type d 2>/dev/null | fzf)
            fi
        fi

        [ -n "$dir" ] && cd "$dir"
    }
fi

# 代碼統計
if command -v tokei &> /dev/null; then
    stats() {
        tokei "${1:-.}" --sort lines
    }
fi

# 詳細的系統更新
sysupdate() {
    echo "正在更新套件清單..."
    sudo apt update
    echo -e "\n可升級的套件："
    apt list --upgradable
    echo -e "\n執行升級..."
    sudo apt upgrade -y
    echo -e "\n清理不需要的套件..."
    sudo apt autoremove -y
    sudo apt autoclean
    echo -e "\n✅ 系統更新完成！"
}

# 建立 Python 虛擬環境
venv() {
    local dir="${1:-venv}"
    if command -v uv &> /dev/null; then
        uv venv "$dir"
    else
        python3 -m venv "$dir"
    fi
    echo "✅ 虛擬環境已建立於 ./$dir"
    echo "啟用方式：source $dir/bin/activate"
}

# -------------------------------------------
# 補全系統
# -------------------------------------------

if command -v gh &> /dev/null; then
    eval "$(gh completion -s bash)" 2>/dev/null
fi

if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
fi

# -------------------------------------------
# 提示符設定
# -------------------------------------------

parse_git_branch() {
    git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/'
}

PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[33m\]$(parse_git_branch)\[\033[00m\]\$ '

BASHRC_EOF

# 插入保留的 conda 配置
if [ -n "$CONDA_INIT" ]; then
    cat >> ~/.bashrc << EOF

# -------------------------------------------
# Conda 配置（保留自原配置）
# -------------------------------------------
$CONDA_INIT
EOF
    print_success "已保留 conda 配置"
fi

# 插入 nvm 配置
if [ -d ~/.nvm ]; then
    cat >> ~/.bashrc << 'EOF'

# -------------------------------------------
# NVM 配置
# -------------------------------------------
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
EOF
    print_success "已保留 nvm 配置"
fi

# 添加 PATH 去重呼叫
cat >> ~/.bashrc << 'EOF'

# -------------------------------------------
# PATH 去重
# -------------------------------------------
__dedupe_path

# -------------------------------------------
# 載入使用者自訂設定（如果存在）
# -------------------------------------------
if [ -f ~/.bashrc.local ]; then
    source ~/.bashrc.local
fi

EOF
print_success "已添加使用者設定載入"

# 添加配置說明註解
cat >> ~/.bashrc << 'EOF'

# ===========================================
# 配置說明
# ===========================================
#
# 原生命令（保持不變）：
#   ls, cat, find, grep, top
#
# 現代化工具（用原名）：
#   eza       - 現代化 ls
#   bat       - 語法高亮的 cat
#   fd        - 更快的 find
#   rg        - 更快的 grep（ripgrep）
#   htop      - 更好的 top
#   delta     - Git diff 美化
#   z <name>  - 智能跳轉目錄（zoxide）
#
# 便捷別名：
#   ll, la, lt        - eza 別名
#   gs, gd, ga, gc    - git 別名
#   sysup             - 快速系統更新
#
# 快捷鍵：
#   Ctrl+R  - fzf 搜尋命令歷史
#   Ctrl+T  - fzf 搜尋檔案
#   Alt+C   - fzf 切換目錄
#
# 自訂函數：
#   fe         - 搜尋並編輯檔案
#   proj       - 快速切換專案目錄
#   sysupdate  - 詳細的系統更新
#   venv       - 建立 Python 虛擬環境
#
# NVIDIA GPU（有 nvidia-smi 時自動載入）：
#   nvidia-check - 檢查 NVIDIA/CUDA 套件是否有可用更新
#   nvidia-hold  - 鎖定已安裝的 NVIDIA/CUDA 套件，避免 sysup 自動升級
#                  裝完 NVIDIA driver 後執行一次即可
#
# ===========================================
EOF

print_success ".bashrc 已建立"

# ================================================
# 步驟 3: 建立 .env
# ================================================
print_header "步驟 3: 設定環境變數"

if [ ! -f ~/.env ]; then
    cat > ~/.env << 'EOF'
# ===========================================
# 環境變數配置檔案
# ===========================================
#
# 請在此添加您的 API Keys
#
# 範例：
# OPENAI_API_KEY="your-key-here"
# GEMINI_API_KEY="your-key-here"
# ANTHROPIC_API_KEY="your-key-here"
#
# ===========================================
EOF
    chmod 600 ~/.env
    print_success ".env 已建立（權限: 600）"
else
    print_info ".env 已存在，跳過建立"
fi

# ================================================
# 步驟 4: 配置 Git
# ================================================
print_header "步驟 4: 配置 Git"

# 檢查 Git 用戶資訊
GIT_USER=$(git config --global user.name 2>/dev/null || echo "")
GIT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")

if [ -z "$GIT_USER" ] || [ -z "$GIT_EMAIL" ]; then
    print_warning "Git 用戶資訊尚未設定"
    echo "請稍後執行："
    echo "  git config --global user.name \"Your Name\""
    echo "  git config --global user.email \"your@email.com\""
else
    print_success "Git 用戶: $GIT_USER <$GIT_EMAIL>"
fi

# Git 基本設定
git config --global init.defaultBranch main
git config --global color.ui auto
git config --global push.autoSetupRemote true
git config --global pull.rebase true
git config --global fetch.prune true
git config --global merge.conflictstyle zdiff3
git config --global rerere.enabled true
git config --global diff.algorithm histogram
git config --global branch.sort -committerdate

# 配置 git-delta
if command -v delta &> /dev/null; then
    git config --global core.pager "delta"
    git config --global interactive.diffFilter "delta --color-only"
    git config --global delta.navigate true
    git config --global delta.side-by-side true
    git config --global delta.line-numbers true
    git config --global delta.light false
    print_success "git-delta 已配置"
fi

# 建立全域 .gitignore
cat > ~/.gitignore_global << 'EOF'
# 環境變數與機密檔案
.env
.env.*
!.env.example
*.pem
*.key
*.p12
*.pfx
credentials.json
token.json
.npmrc
.pypirc

# Linux 系統檔案
*~
.directory
.Trash-*

# IDE 和編輯器
.vscode/
.idea/
*.swp
*.swo

# Node.js
node_modules/
npm-debug.log*

# Python
__pycache__/
*.py[cod]
*.egg-info/
venv/
.venv/
.pytest_cache/

# 資料庫
*.sqlite
*.sqlite3
*.db

# 其他
*.log
.cache/
.DS_Store
EOF

git config --global core.excludesfile ~/.gitignore_global
print_success "全域 .gitignore 已設定"

# 更新 tldr 快取（背景執行）
if command -v tldr &> /dev/null; then
    tldr --update &>/dev/null &
    print_info "tldr 快取更新已在背景執行"
fi

# ================================================
# 步驟 4.5: 設定 Claude Code 全域配置
# ================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ -d "$SCRIPT_DIR/claude" ]; then
    print_info "設定 Claude Code 全域配置..."
    mkdir -p ~/.claude

    # Helper: 建立 symlink（檔案或目錄），自動備份既有內容
    __claude_link() {
        local src="$1" dst="$2"
        if [ -L "$dst" ]; then
            rm "$dst"
        elif [ -e "$dst" ]; then
            mv "$dst" "$dst.backup"
        fi
        ln -sf "$src" "$dst"
    }

    # CLAUDE.md (檔案 symlink)
    if [ -f "$SCRIPT_DIR/claude/CLAUDE.md" ]; then
        __claude_link "$SCRIPT_DIR/claude/CLAUDE.md" ~/.claude/CLAUDE.md
        print_success "已建立 ~/.claude/CLAUDE.md symlink"
    fi

    # settings.json (檔案 symlink)
    if [ -f "$SCRIPT_DIR/claude/settings.json" ]; then
        __claude_link "$SCRIPT_DIR/claude/settings.json" ~/.claude/settings.json
        print_success "已建立 ~/.claude/settings.json symlink"
    fi

    # skills/ (目錄 symlink)
    if [ -d "$SCRIPT_DIR/claude/skills" ]; then
        __claude_link "$SCRIPT_DIR/claude/skills" ~/.claude/skills
        print_success "已建立 ~/.claude/skills/ symlink"
    fi

    unset -f __claude_link
else
    print_info "未找到 claude/ 目錄，跳過 Claude Code 配置"
fi

# ================================================
# 步驟 4.6: 設定 tmux 配置
# ================================================
if [ -f "$SCRIPT_DIR/tmux.conf" ]; then
    print_info "設定 tmux 配置..."
    # 移除舊的 symlink 或檔案
    [ -L ~/.tmux.conf ] && rm ~/.tmux.conf
    [ -f ~/.tmux.conf ] && mv ~/.tmux.conf ~/.tmux.conf.backup
    # 建立 symlink
    ln -sf "$SCRIPT_DIR/tmux.conf" ~/.tmux.conf
    print_success "已建立 ~/.tmux.conf symlink"

    # 確保 tmux-256color terminfo 存在
    if ! infocmp tmux-256color &>/dev/null; then
        print_info "安裝 tmux-256color terminfo..."
        # Linux：嘗試透過套件管理器安裝 ncurses-term
        if command -v apt-get &>/dev/null; then
            sudo apt-get install -y ncurses-term &>/dev/null && print_success "已透過 apt 安裝 ncurses-term"
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y ncurses-base &>/dev/null && print_success "已透過 dnf 安裝 ncurses-base"
        elif command -v pacman &>/dev/null; then
            sudo pacman -S --noconfirm ncurses &>/dev/null && print_success "已透過 pacman 安裝 ncurses"
        else
            # 手動編譯 terminfo
            print_info "嘗試手動編譯 tmux-256color terminfo..."
            tmpfile=$(mktemp)
            cat > "$tmpfile" << 'TERMINFO_EOF'
tmux-256color|tmux with 256 colors,
    use=screen-256color,
    sitm=\E[3m, ritm=\E[23m,
    smso=\E[7m, rmso=\E[27m,
TERMINFO_EOF
            tic -x "$tmpfile" 2>/dev/null
            rm -f "$tmpfile"
        fi
        # 再次確認
        if infocmp tmux-256color &>/dev/null; then
            print_success "tmux-256color terminfo 已就緒"
        else
            print_warning "tmux-256color terminfo 未找到，tmux 將 fallback 至 screen-256color"
        fi
    else
        print_success "tmux-256color terminfo 已存在"
    fi
else
    print_info "未找到 .tmux.conf，跳過 tmux 配置"
fi

# ================================================
# 步驟 5: 驗證
# ================================================
print_header "步驟 5: 驗證安裝"

# 計數器
TOTAL=0
SUCCESS=0

check_tool() {
    TOTAL=$((TOTAL + 1))
    if command -v "$1" &> /dev/null; then
        SUCCESS=$((SUCCESS + 1))
        return 0
    else
        return 1
    fi
}

print_info "檢查已安裝工具..."

# 核心工具
check_tool git && echo "  ✅ git" || echo "  ❌ git"
check_tool wget && echo "  ✅ wget" || echo "  ❌ wget"
check_tool htop && echo "  ✅ htop" || echo "  ❌ htop"
check_tool tree && echo "  ✅ tree" || echo "  ❌ tree"
check_tool tmux && echo "  ✅ tmux" || echo "  ❌ tmux"
check_tool node && echo "  ✅ node" || echo "  ❌ node"
check_tool bun && echo "  ✅ bun" || echo "  ❌ bun"
check_tool jq && echo "  ✅ jq" || echo "  ❌ jq"
check_tool uv && echo "  ✅ uv" || echo "  ❌ uv"

# 現代化工具
check_tool rg && echo "  ✅ ripgrep (rg)" || echo "  ❌ ripgrep"
(check_tool fd || check_tool fdfind) && echo "  ✅ fd" || echo "  ❌ fd"
(check_tool bat || check_tool batcat) && echo "  ✅ bat" || echo "  ❌ bat"
check_tool fzf && echo "  ✅ fzf" || echo "  ❌ fzf"
check_tool eza && echo "  ✅ eza" || echo "  ❌ eza"
check_tool zoxide && echo "  ✅ zoxide" || echo "  ❌ zoxide"
check_tool delta && echo "  ✅ git-delta" || echo "  ❌ git-delta"
check_tool gh && echo "  ✅ GitHub CLI" || echo "  ❌ GitHub CLI"
check_tool yq && echo "  ✅ yq" || echo "  ❌ yq"
check_tool tldr && echo "  ✅ tldr" || echo "  ❌ tldr"
check_tool lazygit && echo "  ✅ lazygit" || echo "  ❌ lazygit"
check_tool dust && echo "  ✅ dust" || echo "  ❌ dust"
check_tool duf && echo "  ✅ duf" || echo "  ❌ duf"
check_tool tokei && echo "  ✅ tokei" || echo "  ❌ tokei"
check_tool sd && echo "  ✅ sd" || echo "  ❌ sd"
check_tool hyperfine && echo "  ✅ hyperfine" || echo "  ❌ hyperfine"
check_tool shellcheck && echo "  ✅ shellcheck" || echo "  ❌ shellcheck"

echo ""
print_success "工具安裝完成: $SUCCESS/$TOTAL"

# 檢查配置檔案
echo ""
print_info "檢查配置檔案..."
[ -f ~/.bashrc ] && echo "  ✅ .bashrc ($(wc -l < ~/.bashrc) 行)" || echo "  ❌ .bashrc"
[ -f ~/.bash_profile ] && echo "  ✅ .bash_profile" || echo "  ❌ .bash_profile"
[ -f ~/.env ] && echo "  ✅ .env (權限: $(stat -c %a ~/.env))" || echo "  ❌ .env"
[ -f ~/.gitignore_global ] && echo "  ✅ .gitignore_global" || echo "  ❌ .gitignore_global"

# 顯示 PATH 統合結果
echo ""
print_info "PATH 設定順序（優先級從高到低）："
echo "  1. \$HOME/.local/bin"
echo "  2. \$HOME/.bun/bin"
echo "  3. \$HOME/.cargo/bin"
echo "  4. \$HOME/go/bin"
echo "  5. (conda 路徑)"
echo "  6. 系統路徑"

# ================================================
# 完成
# ================================================
print_header "安裝完成！"

echo -e "${GREEN}✅ 所有步驟已完成！${NC}"
echo ""
echo "下一步："
echo "  1. 開啟新終端視窗以啟用所有配置"
echo "  2. 執行以下命令測試："
echo -e "     ${BLUE}ll${NC}       # 測試 eza 別名"
echo -e "     ${BLUE}gs${NC}       # 測試 git 別名"
echo -e "     ${BLUE}Ctrl+R${NC}   # 測試 fzf 命令歷史搜尋"
echo ""

if [ -z "$GIT_USER" ] || [ -z "$GIT_EMAIL" ]; then
    echo "  3. 設定 Git 用戶資訊："
    echo -e "     ${BLUE}git config --global user.name \"Your Name\"${NC}"
    echo -e "     ${BLUE}git config --global user.email \"your@email.com\"${NC}"
    echo ""
fi

if command -v gh &> /dev/null; then
    if ! gh auth status &> /dev/null; then
        echo "  4. 登入 GitHub CLI（選擇性）："
        echo -e "     ${BLUE}gh auth login${NC}"
        echo ""
    fi
fi

echo "備份檔案位置："
[ -f ~/.bashrc.backup.$BACKUP_SUFFIX ] && echo "  ~/.bashrc.backup.$BACKUP_SUFFIX"
[ -f ~/.bash_profile.backup.$BACKUP_SUFFIX ] && echo "  ~/.bash_profile.backup.$BACKUP_SUFFIX"

echo ""
echo "使用者設定檔案（不會被覆寫）："
echo -e "  ${BLUE}~/.bashrc.local${NC}        - 個人別名、函數、環境變數"
echo -e "  ${BLUE}~/.bash_profile.local${NC}  - 個人 PATH 設定"
echo "  重複執行腳本時，這些檔案中的設定會被保留"

echo ""
echo "新增工具試用："
echo -e "  ${BLUE}lazygit${NC}               # Git TUI 介面"
echo -e "  ${BLUE}dust${NC}                  # 磁碟空間分析"
echo -e "  ${BLUE}duf${NC}                   # 磁碟使用量顯示"

if command -v nvidia-smi &>/dev/null; then
    echo ""
    echo "NVIDIA GPU 工具："
    echo -e "  ${BLUE}nvidia-check${NC}           # 檢查 NVIDIA/CUDA 套件是否有可用更新"
    echo -e "  ${BLUE}nvidia-hold${NC}            # 鎖定 NVIDIA/CUDA 套件，避免 sysup 自動升級"
    echo "  裝完 NVIDIA driver 後執行一次 nvidia-hold 即可"
fi

echo ""
echo -e "${BLUE}享受您的現代化開發環境！🚀${NC}"
