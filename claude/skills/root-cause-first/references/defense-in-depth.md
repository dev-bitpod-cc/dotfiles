# Defense-in-Depth（多層驗證）

## Overview

修好一個由「無效資料」造成的 bug 後，只在一個地方加檢查感覺就夠了。但那單一檢查會被不同的 code path、重構、或 mock 繞過。

**Core principle: Validate at EVERY layer the data passes through. Make the bug structurally impossible.**

## 為什麼要多層

- 單層驗證 = 「我們修好了這個 bug」
- 多層驗證 = 「我們讓這個 bug 不可能發生」

不同層攔不同情況：入口驗證攔掉多數、業務邏輯攔邊界、環境守衛擋特定情境的危險操作、debug log 在其他層失效時幫你查。

## 四層

### Layer 1：入口驗證（API 邊界拒絕明顯無效輸入）
```python
def create_dataset(name: str, out_dir: str) -> Dataset:
    if not out_dir or not out_dir.strip():
        raise ValueError("out_dir 不可為空")
    if not os.path.isdir(out_dir):
        raise ValueError(f"out_dir 不存在或非目錄: {out_dir}")
    ...
```

### Layer 2：業務邏輯驗證（資料對這個操作合不合理）
```python
def write_partition(out_dir: str, rows: list[dict]):
    if not out_dir:
        raise ValueError("write_partition 需要 out_dir")
    if not rows:
        log.warning("write_partition 收到空 rows，跳過寫入")
        return
    ...
```

### Layer 3：環境守衛（特定情境拒絕危險操作）
```python
def to_parquet_safe(df, path: str):
    # 測試環境拒絕寫到 tmp 以外
    if os.environ.get("ENV") == "test":
        real = os.path.realpath(path)
        if not real.startswith(os.path.realpath(tempfile.gettempdir())):
            raise RuntimeError(f"測試中拒絕寫到 tmp 以外: {path}")
    df.to_parquet(path)
```

### Layer 4：Debug instrumentation（保留鑑識用 context）
```python
def to_parquet_safe(df, path: str):
    log.debug("about to write parquet: path=%s cwd=%s rows=%d", path, os.getcwd(), len(df))
    df.to_parquet(path)
```

## 套用流程

找到 bug 後：
1. **追資料流** — bad value 從哪來、在哪被用（見 `root-cause-tracing.md`）
2. **列出所有檢查點** — 資料經過的每一個點
3. **每層加驗證** — 入口、業務、環境、debug
4. **逐層測試** — 試著繞過 Layer 1，確認 Layer 2 接得住

## 關鍵洞察

四層都有必要。測試時每一層都會攔到其他層漏掉的：不同 code path 繞過入口驗證、mock 繞過業務檢查、跨平台邊界需要環境守衛、debug log 抓出結構性誤用。

**別停在單一驗證點。每一層都加。**
