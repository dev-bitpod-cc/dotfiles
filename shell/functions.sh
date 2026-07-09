#!/usr/bin/env bash
#
# shell/functions.sh — 跨主機共用便利函數（zsh / bash 皆可 source）
#
# 散佈模型：本檔受版控，dotsync 的 git pull 會同步到各主機；互動 rc
# （~/.zshrc / ~/.bashrc）只需一行 `source ~/.dotfiles/shell/functions.sh`
# （setup 預埋、dotsync 幂等補上）。故新增/修改便利函數只要改本檔 + commit
# + dotsync，各主機下次開 shell 即生效——毋須在每台重跑 setup。
#
# 僅放「指向 scripts/ 的便利函數」這類跨機共用邏輯；機器特定設定請走
# ~/.zshrc.local / ~/.bashrc.local。

# Dotfiles 同步
dotsync() { ~/.dotfiles/scripts/dotfiles-sync.sh "$@"; }

# 列出各主機的 tmux session
tmuxls() { ~/.dotfiles/scripts/tmux-ls.sh "$@"; }

# 批次系統更新（mac: brewup；linux: brewup+sysup）；無引數＝本機+遠端（本機若在清單自動扣除）
allup() { ~/.dotfiles/scripts/all-up.sh "$@"; }
