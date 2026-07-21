# Codex 全域設定

本目錄是 `~/.codex/` 的 source of truth，只納入可跨 Linux / macOS 共用、可重建的設定。

## 納入版控

- `config.toml`：Codex 共用預設值
- `AGENTS.md`：Codex 個人全域 guidance；setup/dotsync 連結到 `~/.codex/AGENTS.md`
- `rules/`：不含機器路徑的通用核准規則
- `skills/`：團隊共用 skills
- `skill-building-guide.md`：本 dotfiles 的 Codex skill authoring、eval、validation 與發布流程

## 不納入版控

- `auth.json`
- `history.jsonl`
- `sessions/`
- `shell_snapshots/`
- `log/`
- `logs_*.sqlite`
- `state_*.sqlite`
- `models_cache.json`
- 任何機器相依的 project trust 與本機 token

## 本機設定

若需要保留本機專案信任或其他機器相依設定，請放在：

`~/.codex/config.local.toml`

`setup-linux-env.sh` 與 `setup-mac-env.sh` 會：

1. 將 `~/.dotfiles/codex/config.toml` 同步到 `~/.codex/config.toml`
2. 若偵測到舊的 `[projects."..."]` 區塊，第一次同步時自動搬到 `~/.codex/config.local.toml`
3. 將 `config.local.toml` 內容附加到最終的 `config.toml`

如此可讓共享設定進版控，本機信任設定仍留在本機。

## 跨機散佈

- `scripts/ensure-codex-skills.sh` 幂等連結每個版控 skill 到 `~/.codex/skills/<name>`。
- `scripts/ensure-codex-guidance.sh` 幂等連結 `codex/AGENTS.md` 到 `${CODEX_HOME:-$HOME/.codex}/AGENTS.md`；接管既有實體檔前會備份。
- setup 腳本負責新機初始化；`dotfiles-sync.sh` 在每次 pull 後重跑兩個 helper，讓既有主機不必重跑 setup。
