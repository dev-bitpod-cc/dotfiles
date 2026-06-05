---
name: nc-notify
description: "整合 Notification Center（NC）統一 Telegram 通知服務到 cron / 背景腳本 / pipeline。Use when writing or modifying a cron job, background script (crawler / backfill), or annotation/training pipeline that needs start/done/fail notifications or progress tracking. Chinese triggers：「加通知」「cron」「背景腳本」「回補」「爬蟲」「pipeline」「排程」「跑完通知我」. NC API 細節見 ~/Projects/notification-center/INTEGRATION.md。"
user-invocable: true
allowed-tools: Read, Bash, Edit, Write, Glob, Grep
---

# NC（Notification Center）整合

NC 是統一的 Telegram 通知服務（`db01:8100`）。完整 API 文件與範例：`~/Projects/notification-center/INTEGRATION.md` — status 欄位、`notify_on`、`dedup_key` 用法、完整 payload schema、範例訊息都在那裡查。

## 何時必須整合

| 情境 | 通知 |
|------|------|
| cron 排程、背景腳本（爬蟲/回補）、pipeline（標註/訓練） | **開始 / 完成 / 失敗 必發** |
| 長時間任務（> 5 分鐘） | 加**進度追蹤** |
| 一次性手動腳本 > 10 分鐘 | 建議加 |
| API 服務 | 不需要 |

## 訊息格式

`{動作結果}: {關鍵數據}` — 動作在前、數據在後，一行 ≤ 200 字。

- **不加 emoji**（NC 依 level 自動加）
- **不重複 source**（NC 自動加前綴）
- 三級制：`info`（完成）/ `warning`（非致命異常）/ `error`（需立即處理）

範例：`回補完成: 處理 1203 筆，跳過 12 筆，耗時 4m21s`

## 進度追蹤

task 命名 `{功能}-{動作}`，如 `revenue-backfill`、`risk-v12-train`。

## 環境變數

`NC_API_URL` + `NC_API_KEY`。

## 靜默失敗（硬性）

**NC 不可用不能影響主流程**，所有 NC 呼叫必須 `try/except` 靜默處理。

```python
import os, logging
import httpx  # 或 requests

log = logging.getLogger(__name__)

def nc_notify(message: str, level: str = "info", task: str | None = None, **kwargs):
    """送 NC 通知；失敗只 log warning，絕不 raise（不影響主流程）。
    完整 payload 欄位（status / notify_on / dedup_key 等）見 INTEGRATION.md。"""
    url, key = os.environ.get("NC_API_URL"), os.environ.get("NC_API_KEY")
    if not url or not key:
        return
    try:
        payload = {"message": message, "level": level}
        if task:
            payload["task"] = task
        payload.update(kwargs)  # 依 INTEGRATION.md 補 status / notify_on / dedup_key
        httpx.post(url, json=payload, headers={"Authorization": f"Bearer {key}"}, timeout=5)
    except Exception as e:
        log.warning("NC 通知失敗（不影響主流程）: %s", e)
```

## 整合 checklist（寫腳本時逐項確認）

- [ ] 開始發 `info`、完成發 `info`、失敗（except 區）發 `error`
- [ ] 訊息格式 `{動作結果}: {關鍵數據}`，無 emoji、無 source 前綴、≤ 200 字
- [ ] 長任務（> 5 min）加進度追蹤，task 命名 `{功能}-{動作}`
- [ ] 所有 NC 呼叫 try/except 靜默
- [ ] 讀 `NC_API_URL` / `NC_API_KEY`，缺則跳過
- [ ] payload 進階欄位對照 `INTEGRATION.md`
