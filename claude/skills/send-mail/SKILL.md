---
name: send-mail
description: "透過內部 SMTP relay 寄信給 eland 內部收件人（報表、查詢結果、長任務輸出）。Use when the user explicitly asks to email something — Chinese triggers：「寄信」「mail 給我」「寄給我」「寄到我信箱」「email 給」「把結果寄」. NOT for normal chat replies. 收件人解析優先序：明文 email → 代名詞/未指定皆預設 `jjshen@eland.com.tw` → 不確定才問；勿用 `# userEmail` 推斷。詳見下。"
user-invocable: true
allowed-tools: Bash, Read, Write, Edit
---

# Email（SMTP）寄送

內部 SMTP relay：`172.17.1.143:25`，**no auth**（內網 open relay）。適合把報表、查詢結果、長任務輸出寄給內部 `*@eland.com.tw` 收件人。

## 何時用

- 使用者明確要求「寄信」「mail 給我」
- 或需要把表格/結果用比 chat 更可讀的形式交付（HTML email）

**一般 chat 訊息不要走 email。**

## 收件人解析（★ 重要，依序 fallback）

依下列優先序決定收件人，**命中即停**：

1. **字句中有明文 email** → 直接用那些地址（可多個，逗號分隔）。
   例：「把分析結果寄給 jjshen@eland.com.tw, jjshen@abc.com」→ 收件人 = 這兩個。
2. **代名詞收件人**（寄給我 / mail 給我 / 寄到我信箱）→ **`jjshen@eland.com.tw`**（user 主要工作信箱）。
   例：「把比較表格寄給我」→ `jjshen@eland.com.tw`。
3. **未指定任何收件人**（任務輸出但沒講寄給誰）→ 預設 **`jjshen@eland.com.tw`**。
   例：「測試結束後寄送測試報告」→ `jjshen@eland.com.tw`。
4. **具名但無法解析成 email**（如「寄給老闆」）或仍不確定 → **先問使用者**，可提供 `# userEmail`（當前 session 值）或其他地址作為候選，由使用者確認後再寄。

**NEVER silently use the `# userEmail` system variable as the recipient.** It may differ from the work mailbox and the sandbox may block it — only use it if the user explicitly picks it in step 4.

## 寄件人格式

`<repo-or-task>@eland.com.tw`，如 `aism-news-classifier@eland.com.tw`。

## 內容原則

- **HTML + plain text 雙版本**（plain text 作 fallback）
- 不放 secrets / API keys
- 表格用 `<table border>` 或 plain text aligned columns

## Python 範本

```python
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

msg = MIMEMultipart("alternative")
msg["From"] = "<task>@eland.com.tw"          # 依當前 repo/task 命名
msg["To"] = "<resolved>@eland.com.tw"         # 依收件人解析 fallback：明文 email→代名詞/未指定→jjshen；不確定先問
msg["Subject"] = "..."
msg.attach(MIMEText(text_body, "plain", "utf-8"))
msg.attach(MIMEText(html_body, "html", "utf-8"))  # HTML 可選

with smtplib.SMTP("172.17.1.143", 25, timeout=10) as s:
    s.sendmail(msg["From"], [msg["To"]], msg.as_string())
```

## 寄送前 checklist

- [ ] 收件人已依 fallback 優先序解析（明文 email > 代名詞/未指定→`jjshen@eland.com.tw` > 不確定才問；勿用 `# userEmail` 推斷）
- [ ] 寄件人為 `<repo-or-task>@eland.com.tw`
- [ ] plain text + HTML 雙版本
- [ ] 內容無 secrets / API keys
- [ ] 外部服務呼叫（SMTP）包 try/except，失敗回報使用者
