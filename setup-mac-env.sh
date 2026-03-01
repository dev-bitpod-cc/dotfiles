#!/usr/bin/env bash
#
# macOS 現代化開發環境自動安裝腳本
# 版本：v3.1
# 最後更新：2026-01-12
#
# 使用方式：
#   chmod +x setup-mac-env.sh
#   ./setup-mac-env.sh
#
# 新 Mac 一鍵執行（含 Xcode CLT 安裝 + clone repo）：
#   curl -fsSL dot.bitpod.cc | sh
#
# 特色：
#   - 智能 PATH 統合（保留現有設定、去重、依 macOS/Homebrew 慣例排序）
#   - 所有配置集中在 .zprofile（登入時載入）和 .zshrc（互動式 shell）
#   - 保留 conda、nvm、pyenv 等重要初始化代碼
#
# 注意：此腳本會覆寫 .zshrc 和 .zprofile（會先備份）
# 如果您有自訂配置需要保留，請使用 Markdown + Claude Code 方式
#

# 作業系統檢查（在切換 shell 之前）
if [ "$(uname)" != "Darwin" ]; then
    echo "❌ 此腳本僅適用於 macOS"
    exit 1
fi

# macOS 上自動使用 zsh 執行（若當前不是 zsh）
if [ -z "$ZSH_VERSION" ] && [ -x /bin/zsh ]; then
    exec /bin/zsh "$0" "$@"
fi

set -e  # 遇到錯誤立即退出

# 顏色定義（自動檢測終端是否支持顏色）
if [ -t 1 ] && command -v tput &> /dev/null && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    # 終端支持顏色
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
else
    # 終端不支持顏色，使用空字符串
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    NC=''
fi

# 輔助函數
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

    # .zshrc.local - 如果不存在才建立
    if [ ! -f ~/.zshrc.local ]; then
        cat > ~/.zshrc.local << 'LOCAL_EOF'
# ===========================================
# 使用者自訂設定
# ===========================================
# 此檔案不會被 setup-mac-env.sh 覆寫
# 請在此添加您的個人別名、函數和環境變數
#
# 範例：
#   alias myproj='cd ~/MyProject'
#   export MY_VAR="value"
#
LOCAL_EOF

        # 從現有 .zshrc 提取自訂設定
        if [ -f ~/.zshrc ]; then
            echo "" >> ~/.zshrc.local
            echo "# --- 從原有 .zshrc 提取 ($(date +%Y-%m-%d)) ---" >> ~/.zshrc.local

            # 提取自訂 alias（排除腳本預設的）
            grep -E "^alias " ~/.zshrc 2>/dev/null | \
                grep -v "ll=\|la=\|lt=\|llt=\|gs=\|gd=\|ga=\|gc=\|gp=\|gl=\|gco=\|gb=\|glog=\|gdd=\|brewup=" \
                >> ~/.zshrc.local || true

            # 提取自訂 export（排除腳本預設的）
            grep -E "^export " ~/.zshrc 2>/dev/null | \
                grep -v "PATH=\|FZF_\|BAT_\|CLICOLOR\|NVM_DIR\|PYENV_ROOT" \
                >> ~/.zshrc.local || true
        fi
        print_success "已建立 .zshrc.local"
    else
        print_info ".zshrc.local 已存在，保留使用者設定"
    fi

    # .zprofile.local - 如果不存在才建立
    if [ ! -f ~/.zprofile.local ]; then
        cat > ~/.zprofile.local << 'LOCAL_EOF'
# ===========================================
# 使用者自訂 PATH 和環境設定
# ===========================================
# 此檔案不會被 setup-mac-env.sh 覆寫
# 請在此添加您的個人 PATH 設定
#
# 範例：
#   export PATH="$HOME/my-tools/bin:$PATH"
#
LOCAL_EOF

        # 從現有 .zprofile 提取自訂 PATH
        if [ -f ~/.zprofile ]; then
            echo "" >> ~/.zprofile.local
            echo "# --- 從原有 .zprofile 提取 ($(date +%Y-%m-%d)) ---" >> ~/.zprofile.local

            grep -E "^export PATH=|^PATH=" ~/.zprofile 2>/dev/null | \
                grep -v "/opt/homebrew\|/usr/local\|\.local/bin\|\.bun/bin\|\.cargo/bin\|go/bin\|python/libexec" \
                >> ~/.zprofile.local || true
        fi
        print_success "已建立 .zprofile.local"
    else
        print_info ".zprofile.local 已存在，保留使用者設定"
    fi
}

# 生成 PATH 去重函數（會寫入 .zprofile）
generate_dedupe_function() {
    cat << 'DEDUPE_EOF'
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
DEDUPE_EOF
}

# 檢查是否為 root
if [ "$EUID" -eq 0 ]; then
    print_error "請不要使用 root 執行此腳本"
    exit 1
fi

print_header "macOS 現代化開發環境自動安裝 v3.1"
echo "此腳本將："
echo "  • 檢查並安裝 Homebrew（如需要）"
echo "  • 安裝 28+ 個開發工具（含 Bun）"
echo "  • 智能統合現有 PATH 設定（去重、排序）"
echo "  • 保留 conda、nvm、pyenv 等重要配置"
echo "  • 設定 Git 和其他工具"
echo "  • 預估時間：5-10 分鐘"
echo ""
print_warning "現有的 .zshrc 和 .zprofile 將被備份"
echo ""
echo -n "確定要繼續嗎？[Y/n] "
read -r response
if [[ "$response" =~ ^[Nn]$ ]]; then
    print_info "已取消"
    exit 0
fi

# ================================================
# 步驟 0：系統準備
# ================================================
print_header "步驟 0: 系統準備"

print_info "檢查系統資訊..."
echo "OS: $(sw_vers -productName) $(sw_vers -productVersion)"
echo "架構: $(uname -m)"
echo "Shell: $SHELL"

# 檢查並安裝 Homebrew
if command -v brew &> /dev/null; then
    print_success "Homebrew 已安裝 ($(brew --version | head -1))"
else
    print_warning "Homebrew 未安裝，開始安裝..."

    # 安裝 Homebrew
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # 載入 Homebrew 環境
    if [ -f "/opt/homebrew/bin/brew" ]; then
        # Apple Silicon Mac
        eval "$(/opt/homebrew/bin/brew shellenv)"
        print_success "Homebrew 已安裝（Apple Silicon）"
    elif [ -f "/usr/local/bin/brew" ]; then
        # Intel Mac
        eval "$(/usr/local/bin/brew shellenv)"
        print_success "Homebrew 已安裝（Intel Mac）"
    fi
fi

# 更新 Homebrew
print_info "更新 Homebrew..."
brew update -q

# 檢查 Command Line Tools
if xcode-select -p &> /dev/null; then
    print_success "Xcode Command Line Tools 已安裝"
else
    print_warning "Xcode Command Line Tools 未安裝"
    print_info "正在觸發安裝提示..."
    git --version 2>/dev/null
    print_info "請在彈出視窗中點擊「安裝」，安裝完成後重新執行此腳本"
    exit 1
fi

print_success "系統準備完成"

# ================================================
# 步驟 1: 安裝開發工具
# ================================================
print_header "步驟 1: 安裝開發工具"

print_info "安裝核心工具和現代化 CLI 工具..."
print_info "這可能需要幾分鐘，請耐心等候..."

# 添加 Bun 官方 Homebrew tap
print_info "添加 Bun 官方 tap..."
brew tap oven-sh/bun 2>/dev/null || true

# 一次性安裝所有工具
brew install \
  git \
  gh \
  wget \
  htop \
  tree \
  tmux \
  node \
  oven-sh/bun/bun \
  python \
  uv \
  jq \
  yq \
  httpie \
  git-delta \
  ripgrep \
  fd \
  bat \
  fzf \
  eza \
  zoxide \
  tlrc \
  tokei \
  sd \
  hyperfine \
  lazygit \
  dust \
  duf \
  shellcheck \
  2>&1 | grep -v "already installed" || true

print_success "工具安裝完成"

# 條件安裝：Swift 開發工具
if [ -d "/Applications/Xcode.app" ]; then
    print_info "檢測到 Xcode.app，安裝 Swift 開發工具..."
    brew install swiftlint xcbeautify 2>&1 | grep -v "already installed" || true
    print_success "Swift 工具安裝完成"
else
    print_info "未檢測到 Xcode.app，跳過 swiftlint 和 xcbeautify"
fi

# ================================================
# 步驟 2: 設定 fzf Shell 整合
# ================================================
print_header "步驟 2: 設定 fzf Shell 整合"

print_info "執行 fzf 安裝腳本..."
$(brew --prefix)/opt/fzf/install --key-bindings --completion --no-update-rc --no-bash --no-fish

print_success "fzf Shell 整合完成"

# ================================================
# 步驟 3: 建立配置檔案
# ================================================
print_header "步驟 3: 建立配置檔案"

# 備份現有配置
BACKUP_SUFFIX=$(date +%Y%m%d_%H%M%S)

if [ -f ~/.zshrc ]; then
    cp ~/.zshrc ~/.zshrc.backup.$BACKUP_SUFFIX
    print_success "已備份 .zshrc → .zshrc.backup.$BACKUP_SUFFIX"
fi

if [ -f ~/.zprofile ]; then
    cp ~/.zprofile ~/.zprofile.backup.$BACKUP_SUFFIX
    print_success "已備份 .zprofile → .zprofile.backup.$BACKUP_SUFFIX"
fi

# 檢測並保存重要的初始化代碼
print_info "分析現有配置..."

CONDA_INIT=""
NVM_INIT=""
PYENV_INIT=""

# 從 .zshrc 或 .zprofile 提取 conda 初始化
for config_file in ~/.zshrc ~/.zprofile; do
    if [ -f "$config_file" ] && grep -q "conda initialize" "$config_file"; then
        CONDA_INIT=$(sed -n '/>>> conda initialize >>>/,/<<< conda initialize <<</p' "$config_file")
        print_info "檢測到 conda 配置，將會保留"
        break
    fi
done

# 檢測 nvm
if [ -d ~/.nvm ]; then
    print_info "檢測到 nvm，將會保留配置"
fi

# 檢測 pyenv
if [ -d ~/.pyenv ]; then
    print_info "檢測到 pyenv，將會保留配置"
fi

# 提取使用者自訂設定到 .local 檔案
extract_user_settings

# 顯示將要設定的 PATH 順序（優先級從高到低）
echo ""
echo -e "${CYAN:-}PATH 優先級順序（高到低）：${NC:-}"
echo "  [1]  \$HOME/.local/bin                    # 用戶本地程式（uv 等）"
echo "  [2]  Homebrew Python libexec/bin         # python 命令（非 python3）"
echo "  [3]  \$HOME/.bun/bin                      # Bun 全域套件"
echo "  [4]  \$HOME/.cargo/bin                    # Cargo (Rust)"
echo "  [5]  \$HOME/go/bin                        # Go"
echo "  [6]  pyenv 路徑                          # 如有安裝"
echo "  [7]  rbenv 路徑                          # 如有安裝"
echo "  [8]  nvm 路徑                            # 由 nvm 管理"
echo "  [9]  conda 路徑                          # 由 conda init 管理"
echo "  [20] /opt/homebrew/bin (Apple Silicon)   # Homebrew"
echo "  [23] /usr/local/bin (Intel Mac)          # Homebrew"
echo "  [30] /usr/bin, /bin 等                   # 系統路徑"
echo ""

# 建立 .zprofile
print_info "建立 .zprofile..."
cat > ~/.zprofile << 'ZPROFILE_EOF'
# ===========================================
# 登入 Shell 配置（macOS）
# ===========================================
# 版本：v3.1
# 最後更新：2026-01-12
# 自動生成於：macOS 環境設定腳本
#
# 策略：
#   - PATH 已統合並依 macOS/Homebrew 慣例排序
#   - 高優先級路徑在前（用戶程式 > Homebrew Python > Bun > ...）
#   - 自動去重，避免重複路徑
# ===========================================

ZPROFILE_EOF

# 插入 PATH 去重函數
generate_dedupe_function >> ~/.zprofile

cat >> ~/.zprofile << 'ZPROFILE_EOF'

# -------------------------------------------
# Homebrew 環境設定
# -------------------------------------------

# 自動偵測 Homebrew 路徑（支援 Apple Silicon 和 Intel）
if [ -f "/opt/homebrew/bin/brew" ]; then
    # Apple Silicon Mac
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -f "/usr/local/bin/brew" ]; then
    # Intel Mac
    eval "$(/usr/local/bin/brew shellenv)"
fi

# -------------------------------------------
# PATH 設定（按優先級從低到高添加，最後添加的排最前）
# -------------------------------------------

# 優先級 6: Go
[ -d "$HOME/go/bin" ] && export PATH="$HOME/go/bin:$PATH"

# 優先級 5: Cargo (Rust)
if [ -f "$HOME/.cargo/env" ]; then
    source "$HOME/.cargo/env"
elif [ -d "$HOME/.cargo/bin" ]; then
    export PATH="$HOME/.cargo/bin:$PATH"
fi

# 優先級 3: Bun 全域套件
# Bun 全局安裝的套件（bun install -g）都放在 ~/.bun/bin
# Homebrew 安裝的 bun 執行檔在 /opt/homebrew/bin，但全局套件仍在 ~/.bun/bin
[ -d "$HOME/.bun/bin" ] && export PATH="$HOME/.bun/bin:$PATH"

# npm 全域套件（相容性備用，優先級低於 bun）
[ -d "$HOME/.npm-global/bin" ] && export PATH="$HOME/.npm-global/bin:$PATH"

# 優先級 2: Homebrew Python 無版本路徑（python 而非 python3）
if [ -d "/opt/homebrew/opt/python/libexec/bin" ]; then
    # Apple Silicon
    export PATH="/opt/homebrew/opt/python/libexec/bin:$PATH"
elif [ -d "/usr/local/opt/python/libexec/bin" ]; then
    # Intel Mac
    export PATH="/usr/local/opt/python/libexec/bin:$PATH"
fi

# 優先級 1: 用戶本地程式（最高優先級）
[ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH"

ZPROFILE_EOF

# 插入保留的 conda 配置
if [ -n "$CONDA_INIT" ]; then
    cat >> ~/.zprofile << EOF

# -------------------------------------------
# Conda 配置（保留自原配置）
# -------------------------------------------
$CONDA_INIT
EOF
    print_success "已保留 conda 配置"
fi

# 插入 nvm 配置
if [ -d ~/.nvm ]; then
    cat >> ~/.zprofile << 'EOF'

# -------------------------------------------
# NVM 配置
# -------------------------------------------
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
EOF
    print_success "已保留 nvm 配置"
fi

# 插入 pyenv 配置
if [ -d ~/.pyenv ]; then
    cat >> ~/.zprofile << 'EOF'

# -------------------------------------------
# pyenv 配置
# -------------------------------------------
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
EOF
    print_success "已保留 pyenv 配置"
fi

# 添加 PATH 去重和載入使用者設定
cat >> ~/.zprofile << 'EOF'

# -------------------------------------------
# PATH 去重
# -------------------------------------------
__dedupe_path

# -------------------------------------------
# 載入使用者自訂設定（如果存在）
# -------------------------------------------
# .zprofile.local 用於保留使用者原有的自訂 PATH 和環境變數
# 此檔案不會被腳本覆寫，可安全地添加個人設定
[ -f ~/.zprofile.local ] && source ~/.zprofile.local

EOF

print_success ".zprofile 已建立"

# 建立 .zshrc
print_info "建立 .zshrc..."
cat > ~/.zshrc << 'EOF'
# ===========================================
# 現代化開發環境配置（macOS）
# ===========================================
# 版本：v3.1
# 最後更新：2026-01-12
# 自動生成於：macOS 環境設定腳本
#
# 策略：
#   - PATH 設定已集中在 .zprofile
#   - 此檔案專注於別名、函數、工具配置
#   - 保留原生命令（ls, cat, find, grep）
#   - 現代化工具用原名（eza, bat, fd, rg）
# ===========================================

# -------------------------------------------
# 額外 PATH（低優先級，附加在末尾）
# -------------------------------------------

# LM Studio CLI（如果有使用，避免重複添加）
if [[ -d "$HOME/.lmstudio/bin" ]] && [[ ! "$PATH" == *"$HOME/.lmstudio/bin"* ]]; then
    export PATH="$PATH:$HOME/.lmstudio/bin"
fi

# -------------------------------------------
# 工具初始化
# -------------------------------------------

# fzf - 模糊搜尋（啟用快捷鍵）
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# zoxide - 智能目錄跳轉
if command -v zoxide &> /dev/null; then
    eval "$(zoxide init zsh)"
fi

# -------------------------------------------
# 環境變數
# -------------------------------------------
if [ -f ~/.env ]; then
    set -a
    source ~/.env
    set +a
fi

# -------------------------------------------
# 便捷別名
# -------------------------------------------

# eza 的便捷別名
if command -v eza &> /dev/null; then
    alias ll='eza -l'
    alias la='eza -la'
    alias lt='eza --tree'
    alias llt='eza -l --tree'
fi

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

# 系統更新
alias brewup='(cd ~/.dotfiles && git pull 2>/dev/null); brew update && brew upgrade && brew cleanup'

# -------------------------------------------
# fzf 配置
# -------------------------------------------
if command -v fzf &> /dev/null; then
    export FZF_DEFAULT_OPTS='
      --height 40%
      --layout=reverse
      --border
      --preview "bat --color=always --style=numbers --line-range :500 {} 2>/dev/null || cat {}"
      --preview-window=right:50%
    '

    if command -v fd &> /dev/null; then
        export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
        export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
        export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
    fi

    if command -v bat &> /dev/null; then
        export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range :500 {}'"
    fi

    if command -v eza &> /dev/null; then
        export FZF_ALT_C_OPTS="--preview 'eza --tree --level=2 --color=always {}'"
    fi
fi

# -------------------------------------------
# bat 配置
# -------------------------------------------
if command -v bat &> /dev/null; then
    export BAT_THEME="TwoDark"
    export BAT_PAGER="less -RF"
fi

# -------------------------------------------
# 其他設定
# -------------------------------------------
export CLICOLOR=1
export EDITOR=vim
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt SHARE_HISTORY

# -------------------------------------------
# 自訂函數
# -------------------------------------------

# 快速查找並編輯檔案
if command -v fzf &> /dev/null && command -v fd &> /dev/null; then
    fe() {
        local file
        file=$(fd --type f --hidden --follow --exclude .git | fzf --preview 'bat --color=always --style=numbers {}' 2>/dev/null || fzf)
        [ -n "$file" ] && ${EDITOR:-vim} "$file"
    }
fi

# 快速切換到專案目錄
if command -v fzf &> /dev/null && command -v fd &> /dev/null; then
    proj() {
        local dir
        if [ -d ~/Projects ]; then
            dir=$(fd --type d --max-depth 3 . ~/Projects | fzf --preview 'eza --tree --level=2 {}' 2>/dev/null || fzf)
        else
            dir=$(fd --type d --max-depth 3 . ~ | fzf --preview 'eza --tree --level=2 {}' 2>/dev/null || fzf)
        fi
        [ -n "$dir" ] && cd "$dir"
    }
fi

# 快速查看代碼統計
if command -v tokei &> /dev/null; then
    stats() {
        tokei "${1:-.}" --sort lines
    }
fi

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
autoload -Uz compinit
compinit

if command -v gh &> /dev/null; then
    eval "$(gh completion -s zsh)" 2>/dev/null
fi

# -------------------------------------------
# 提示符設定
# -------------------------------------------
setopt PROMPT_SUBST
autoload -Uz vcs_info
precmd() { vcs_info }
zstyle ':vcs_info:git:*' formats ' (%b)'

PROMPT='%n@%m %F{cyan}%~%f%F{yellow}${vcs_info_msg_0_}%f %# '

# -------------------------------------------
# 載入使用者自訂設定（如果存在）
# -------------------------------------------
if [ -f ~/.zshrc.local ]; then
    source ~/.zshrc.local
fi
EOF

print_success ".zshrc 已建立"

# ================================================
# 步驟 4: 建立 .env
# ================================================
print_header "步驟 4: 設定環境變數"

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
# 步驟 5: 配置 Git
# ================================================
print_header "步驟 5: 配置 Git"

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

# macOS 系統檔案
.DS_Store
.AppleDouble
.LSOverride

# IDE 和編輯器
.vscode/
.idea/
*.swp
*.swo
*~

# Node.js
node_modules/
npm-debug.log*

# Python
__pycache__/
*.py[cod]
*.egg-info/
venv/
.venv/

# 資料庫
*.sqlite
*.sqlite3
*.db

# 其他
*.log
.cache/
EOF

git config --global core.excludesfile ~/.gitignore_global
print_success "全域 .gitignore 已設定"

# 更新 tldr 快取
if command -v tldr &> /dev/null; then
    tldr --update &>/dev/null &
    print_info "tldr 快取更新已在背景執行"
fi

# ================================================
# 步驟 5.5: 設定 Claude Code 全域配置
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

    # commands/ (目錄 symlink)
    if [ -d "$SCRIPT_DIR/claude/commands" ]; then
        __claude_link "$SCRIPT_DIR/claude/commands" ~/.claude/commands
        print_success "已建立 ~/.claude/commands/ symlink"
    fi

    unset -f __claude_link
else
    print_info "未找到 claude/ 目錄，跳過 Claude Code 配置"
fi

# ================================================
# 步驟 5.6: 設定 tmux 配置
# ================================================
if [ -f "$SCRIPT_DIR/.tmux.conf" ]; then
    print_info "設定 tmux 配置..."
    # 移除舊的 symlink 或檔案
    [ -L ~/.tmux.conf ] && rm ~/.tmux.conf
    [ -f ~/.tmux.conf ] && mv ~/.tmux.conf ~/.tmux.conf.backup
    # 建立 symlink
    ln -sf "$SCRIPT_DIR/.tmux.conf" ~/.tmux.conf
    print_success "已建立 ~/.tmux.conf symlink"

    # 確保 tmux-256color terminfo 存在（安裝至 ~/.terminfo/）
    if ! infocmp tmux-256color &>/dev/null; then
        print_info "安裝 tmux-256color terminfo..."
        installed=false
        # 嘗試從 Homebrew ncurses 匯出再編譯到 ~/.terminfo/
        if command -v brew &>/dev/null; then
            NCURSES_DB="$(brew --prefix ncurses 2>/dev/null)/share/terminfo"
            if [ -d "$NCURSES_DB" ]; then
                tmpfile=$(mktemp)
                TERMINFO_DIRS="$NCURSES_DB" infocmp -x tmux-256color > "$tmpfile" 2>/dev/null \
                    && tic -x "$tmpfile" 2>/dev/null \
                    && installed=true
                rm -f "$tmpfile"
            fi
        fi
        # Homebrew 沒有的話，用內嵌的最小定義編譯
        if ! $installed; then
            tmpfile=$(mktemp)
            cat > "$tmpfile" << 'TERMINFO_EOF'
tmux-256color|tmux with 256 colors,
    use=screen-256color,
    sitm=\E[3m, ritm=\E[23m,
    smso=\E[7m, rmso=\E[27m,
TERMINFO_EOF
            tic -x "$tmpfile" 2>/dev/null && installed=true
            rm -f "$tmpfile"
        fi
        # 確認結果
        if infocmp tmux-256color &>/dev/null; then
            print_success "tmux-256color terminfo 已安裝至 ~/.terminfo/"
        else
            print_warning "tmux-256color terminfo 安裝失敗，tmux 將 fallback 至 screen-256color"
        fi
    else
        print_success "tmux-256color terminfo 已存在"
    fi
else
    print_info "未找到 .tmux.conf，跳過 tmux 配置"
fi

# ================================================
# 步驟 6: 驗證
# ================================================
print_header "步驟 6: 驗證安裝"

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
check_tool gh && echo "  ✅ gh" || echo "  ❌ gh"
check_tool wget && echo "  ✅ wget" || echo "  ❌ wget"
check_tool htop && echo "  ✅ htop" || echo "  ❌ htop"
check_tool tree && echo "  ✅ tree" || echo "  ❌ tree"
check_tool tmux && echo "  ✅ tmux" || echo "  ❌ tmux"
check_tool node && echo "  ✅ node" || echo "  ❌ node"
check_tool bun && echo "  ✅ bun" || echo "  ❌ bun"
check_tool python3 && echo "  ✅ python3" || echo "  ❌ python3"
check_tool uv && echo "  ✅ uv" || echo "  ❌ uv"
check_tool jq && echo "  ✅ jq" || echo "  ❌ jq"
check_tool yq && echo "  ✅ yq" || echo "  ❌ yq"

# 現代化工具
check_tool rg && echo "  ✅ ripgrep (rg)" || echo "  ❌ ripgrep"
check_tool fd && echo "  ✅ fd" || echo "  ❌ fd"
check_tool bat && echo "  ✅ bat" || echo "  ❌ bat"
check_tool fzf && echo "  ✅ fzf" || echo "  ❌ fzf"
check_tool eza && echo "  ✅ eza" || echo "  ❌ eza"
check_tool zoxide && echo "  ✅ zoxide" || echo "  ❌ zoxide"
check_tool delta && echo "  ✅ git-delta" || echo "  ❌ git-delta"
check_tool http && echo "  ✅ httpie" || echo "  ❌ httpie"
check_tool tldr && echo "  ✅ tldr" || echo "  ❌ tldr"
check_tool tokei && echo "  ✅ tokei" || echo "  ❌ tokei"
check_tool sd && echo "  ✅ sd" || echo "  ❌ sd"
check_tool hyperfine && echo "  ✅ hyperfine" || echo "  ❌ hyperfine"
check_tool lazygit && echo "  ✅ lazygit" || echo "  ❌ lazygit"
check_tool dust && echo "  ✅ dust" || echo "  ❌ dust"
check_tool duf && echo "  ✅ duf" || echo "  ❌ duf"
check_tool shellcheck && echo "  ✅ shellcheck" || echo "  ❌ shellcheck"

echo ""
print_success "工具安裝完成: $SUCCESS/$TOTAL"

# 檢查配置檔案
echo ""
print_info "檢查配置檔案..."
[ -f ~/.zshrc ] && echo "  ✅ .zshrc" || echo "  ❌ .zshrc"
[ -f ~/.zprofile ] && echo "  ✅ .zprofile" || echo "  ❌ .zprofile"
[ -f ~/.env ] && echo "  ✅ .env" || echo "  ❌ .env"
[ -f ~/.fzf.zsh ] && echo "  ✅ .fzf.zsh" || echo "  ❌ .fzf.zsh"
[ -f ~/.gitignore_global ] && echo "  ✅ .gitignore_global" || echo "  ❌ .gitignore_global"

# 顯示 PATH 統合結果
echo ""
print_info "PATH 設定順序（優先級從高到低）："
echo "  1. \$HOME/.local/bin"
echo "  2. Homebrew Python libexec/bin"
echo "  3. \$HOME/.bun/bin"
echo "  4. \$HOME/.cargo/bin"
echo "  5. \$HOME/go/bin"
echo "  6. pyenv/rbenv 路徑"
echo "  7. nvm 路徑"
echo "  8. conda 路徑"
echo "  9. Homebrew 路徑"
echo "  11. 系統路徑"

# ================================================
# 步驟 6.2: 建立詳細驗證腳本
# ================================================
echo ""
print_info "建立詳細驗證腳本..."

cat > /tmp/verify_setup.sh << 'VERIFY_EOF'
#!/bin/zsh

# 載入配置
source ~/.zprofile 2>/dev/null
source ~/.zshrc 2>/dev/null

echo "================================================"
echo "  macOS 開發環境驗證"
echo "================================================"

# 1. 檢查系統資訊
echo -e "\n=== 系統資訊 ==="
echo "OS: $(sw_vers -productName) $(sw_vers -productVersion)"
echo "架構: $(uname -m)"
echo "Shell: $SHELL"
echo "Homebrew: $(brew --version | head -1)"

# 2. 檢查核心工具
echo -e "\n=== 核心工具 ==="
git --version 2>/dev/null || echo "❌ git 未安裝"
gh --version 2>/dev/null | head -1 || echo "❌ gh 未安裝"
wget --version 2>/dev/null | head -1 || echo "❌ wget 未安裝"
htop --version 2>/dev/null || echo "❌ htop 未安裝"
tree --version 2>/dev/null || echo "❌ tree 未安裝"
tmux -V 2>/dev/null || echo "❌ tmux 未安裝"
node --version 2>/dev/null || echo "❌ node 未安裝"
bun --version 2>/dev/null || echo "❌ bun 未安裝"

# 3. 檢查 Python
echo -e "\n=== Python ==="
python3 --version 2>/dev/null || echo "❌ python3 未安裝"
python --version 2>/dev/null || echo "⚠️ python 命令不可用（需要新終端）"
uv --version 2>/dev/null || echo "❌ uv 未安裝"

# 4. 檢查現代化 CLI 工具
echo -e "\n=== 現代化 CLI 工具 ==="
rg --version 2>/dev/null | head -1 || echo "❌ ripgrep 未安裝"
fd --version 2>/dev/null || echo "❌ fd 未安裝"
bat --version 2>/dev/null | head -1 || echo "❌ bat 未安裝"
fzf --version 2>/dev/null || echo "❌ fzf 未安裝"
eza --version 2>/dev/null | head -1 || echo "❌ eza 未安裝"
zoxide --version 2>/dev/null || echo "❌ zoxide 未安裝"
delta --version 2>/dev/null || echo "❌ git-delta 未安裝"
http --version 2>/dev/null || echo "❌ httpie 未安裝"
jq --version 2>/dev/null || echo "❌ jq 未安裝"
yq --version 2>/dev/null | head -1 || echo "❌ yq 未安裝"
tldr --version 2>/dev/null || echo "❌ tldr 未安裝"
tokei --version 2>/dev/null || echo "❌ tokei 未安裝"
sd --version 2>/dev/null || echo "❌ sd 未安裝"
hyperfine --version 2>/dev/null || echo "❌ hyperfine 未安裝"
lazygit --version 2>/dev/null | head -1 || echo "❌ lazygit 未安裝"
dust --version 2>/dev/null || echo "❌ dust 未安裝"
duf --version 2>/dev/null || echo "❌ duf 未安裝"

# 5. 檢查 Swift 工具
echo -e "\n=== Swift 工具 ==="
if [ -d "/Applications/Xcode.app" ]; then
    swiftlint version 2>/dev/null || echo "❌ swiftlint 未安裝"
    xcbeautify --version 2>/dev/null || echo "❌ xcbeautify 未安裝"
else
    echo "未安裝 Xcode.app"
fi

# 6. 檢查原生命令
echo -e "\n=== 檢查原生命令 ==="
type ls cat find grep top 2>/dev/null | head -5

# 7. 檢查便捷別名
echo -e "\n=== 檢查便捷別名 ==="
alias ll 2>/dev/null && echo "✅ ll 別名存在" || echo "⚠️ ll 別名不存在（需要新終端）"
alias la 2>/dev/null && echo "✅ la 別名存在" || echo "⚠️ la 別名不存在（需要新終端）"
alias gs 2>/dev/null && echo "✅ gs 別名存在" || echo "⚠️ gs 別名不存在（需要新終端）"

# 8. 檢查 Git 配置
echo -e "\n=== Git 配置 ==="
GIT_USER=$(git config --global user.name)
GIT_EMAIL=$(git config --global user.email)
if [ -z "$GIT_USER" ]; then
    echo "⚠️ Git 用戶名未設定"
else
    echo "✅ User: $GIT_USER"
fi
if [ -z "$GIT_EMAIL" ]; then
    echo "⚠️ Git Email 未設定"
else
    echo "✅ Email: $GIT_EMAIL"
fi
echo "Pager: $(git config --global core.pager || echo "未設定")"
echo "Excludes: $(git config --global core.excludesfile || echo "未設定")"

# 9. 檢查 GitHub CLI
echo -e "\n=== GitHub CLI ==="
if command -v gh &> /dev/null; then
    gh auth status 2>&1 | head -3
else
    echo "❌ GitHub CLI 未安裝"
fi

# 10. 檢查配置檔案
echo -e "\n=== 配置檔案 ==="
[ -f ~/.zshrc ] && echo "✅ .zshrc 存在 ($(wc -l < ~/.zshrc) 行)" || echo "❌ .zshrc 不存在"
[ -f ~/.zprofile ] && echo "✅ .zprofile 存在" || echo "❌ .zprofile 不存在"
[ -f ~/.env ] && echo "✅ .env 存在 (權限: $(stat -f %Lp ~/.env))" || echo "❌ .env 不存在"
[ -f ~/.fzf.zsh ] && echo "✅ .fzf.zsh 存在" || echo "❌ .fzf.zsh 不存在"
[ -f ~/.gitignore_global ] && echo "✅ .gitignore_global 存在" || echo "❌ .gitignore_global 不存在"

# 11. 顯示 PATH 順序
echo -e "\n=== PATH 順序（前 15 個）==="
echo $PATH | tr ':' '\n' | head -15 | nl

# 12. 檢查自訂函數
echo -e "\n=== 檢查自訂函數 ==="
type fe 2>/dev/null | grep -q "function" && echo "✅ fe 函數存在" || echo "⚠️ fe 函數不存在（需要新終端）"
type proj 2>/dev/null | grep -q "function" && echo "✅ proj 函數存在" || echo "⚠️ proj 函數不存在（需要新終端）"
type stats 2>/dev/null | grep -q "function" && echo "✅ stats 函數存在" || echo "⚠️ stats 函數不存在（需要新終端）"

echo -e "\n================================================"
echo "  驗證完成！"
echo "================================================"
echo ""
echo "⚠️ 如果別名或函數顯示不存在，請開啟新終端視窗"
VERIFY_EOF

chmod +x /tmp/verify_setup.sh

echo ""
print_info "執行詳細驗證..."
echo ""
/tmp/verify_setup.sh

# ================================================
# 完成
# ================================================
print_header "安裝完成！"

echo -e "${GREEN}✅ 所有步驟已完成！${NC}"
echo ""
echo -e "⚠️  ${YELLOW}重要：請開啟新終端視窗以啟用所有配置${NC}"
echo ""
echo "需要新終端才能使用的功能："
echo -e "  • ${BLUE}python${NC} 命令（目前只有 python3 可用）"
echo -e "  • 所有別名：${BLUE}ll, la, lt, gs, gd${NC} 等"
echo -e "  • 自訂函數：${BLUE}fe, proj, stats${NC}"
echo -e "  • zoxide 智能跳轉：${BLUE}z${NC} 命令"
echo "  • 新的提示符（顯示 Git 分支）"
echo ""
echo "開啟新終端後的快速驗證："
echo -e "  ${BLUE}python --version${NC}    # 應顯示 Python 3.x"
echo -e "  ${BLUE}ll${NC}                  # 應顯示彩色列表"
echo -e "  ${BLUE}gs${NC}                  # 應執行 git status"
echo ""
echo "試用 fzf 快捷鍵（互動式）："
echo -e "  ${BLUE}Ctrl+R${NC}  - 搜尋命令歷史"
echo -e "  ${BLUE}Ctrl+T${NC}  - 搜尋檔案"
echo -e "  ${BLUE}Alt+C${NC}   - 切換目錄"
echo ""

if [ -z "$GIT_USER" ] || [ -z "$GIT_EMAIL" ]; then
    echo "下一步：設定 Git 用戶資訊"
    echo -e "  ${BLUE}git config --global user.name \"Your Name\"${NC}"
    echo -e "  ${BLUE}git config --global user.email \"your@email.com\"${NC}"
    echo ""
fi

if command -v gh &> /dev/null; then
    if ! gh auth status &> /dev/null; then
        echo "可選：登入 GitHub CLI"
        echo -e "  ${BLUE}gh auth login${NC}"
        echo ""
    fi
fi

echo "備份檔案位置："
[ -f ~/.zshrc.backup.$BACKUP_SUFFIX ] && echo "  ~/.zshrc.backup.$BACKUP_SUFFIX"
[ -f ~/.zprofile.backup.$BACKUP_SUFFIX ] && echo "  ~/.zprofile.backup.$BACKUP_SUFFIX"

echo ""
echo "使用者設定檔案（不會被覆寫）："
echo -e "  ${BLUE}~/.zshrc.local${NC}    - 個人別名、函數、環境變數"
echo -e "  ${BLUE}~/.zprofile.local${NC} - 個人 PATH 設定"
echo "  重複執行腳本時，這些檔案中的設定會被保留"

echo ""
echo "新增工具試用："
echo -e "  ${BLUE}lazygit${NC}           # Git TUI 介面"
echo -e "  ${BLUE}dust${NC}              # 磁碟空間分析"
echo -e "  ${BLUE}duf${NC}               # 磁碟使用量顯示"

echo ""
echo "PATH 說明："
echo "  • 高優先級路徑（用戶程式、Homebrew Python）排在前面"
echo "  • 自動去重，避免重複路徑"
echo "  • conda/nvm/pyenv 等工具配置已保留"
echo ""

echo -e "詳細驗證腳本已保存至: ${BLUE}/tmp/verify_setup.sh${NC}"
echo -e "可隨時執行: ${BLUE}/tmp/verify_setup.sh${NC}"
echo ""
echo -e "${BLUE}享受您的現代化開發環境！🚀${NC}"
