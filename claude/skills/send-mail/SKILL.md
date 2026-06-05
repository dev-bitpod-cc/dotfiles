---
name: send-mail
description: "透過內部 SMTP relay 寄信給 eland 內部收件人（報表、查詢結果、長任務輸出）。Use when the user explicitly asks to email something — Chinese triggers：「寄信」「mail 給我」「寄給我」「寄到我信箱」「email 給」「把結果寄」. NOT for normal chat replies. 收件人代名詞解析 + HTML/plain text 雙版本範本見下。"
user-invocable: true
allowed-tools: Bash, Read, Write, Edit
---

# Email（SMTP）寄送

內部 SMTP relay：`172.17.1.143:25`，**no auth**（內網 open relay）。適合把報表、查詢結果、長任務輸出寄給內部 `*@eland.com.tw` 收件人。

## 何時用

- 使用者明確要求「寄信」「mail 給我」
- 或需要把表格/結果用比 chat 更可讀的形式交付（HTML email）

**一般 chat 訊息不要走 email。**

## 收件人解析（★ 重要）

- 「寄給我」「mail 給我」「寄到我信箱」等代名詞 → **`jjshen@eland.com.tw`**（user 主要工作信箱）
- 其他收件人由使用者**明確指定**。**不要用 `# userEmail` 等系統變數推斷**（sandbox 會擋，且可能是錯的位址）。沒指定就**先問**。

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
msg["To"] = "<user-confirmed>@eland.com.tw"   # 代名詞→jjshen；其他須使用者指定
msg["Subject"] = "..."
msg.attach(MIMEText(text_body, "plain", "utf-8"))
msg.attach(MIMEText(html_body, "html", "utf-8"))  # HTML 可選

with smtplib.SMTP("172.17.1.143", 25, timeout=10) as s:
    s.sendmail(msg["From"], [msg["To"]], msg.as_string())
```

## 寄送前 checklist

- [ ] 收件人已確認（代名詞→`jjshen@eland.com.tw`；其他須使用者明確指定，未指定先問）
- [ ] 寄件人為 `<repo-or-task>@eland.com.tw`
- [ ] plain text + HTML 雙版本
- [ ] 內容無 secrets / API keys
- [ ] 外部服務呼叫（SMTP）包 try/except，失敗回報使用者
