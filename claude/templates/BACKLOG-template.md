<!--
backlog.md — 專案未結案待辦（技術債 + 已知缺口）。每項建立時就帶 `B-YYYYMMDD-slug`。
本檔只收「尚未解決、直到被做掉才會消失」的東西；decision／dead end 屬 history，直接寫入
`docs/archive/` 的 event-time shard，不留在這裡。
-->

# Backlog

待辦清單:技術債與已知缺口(更新日期:YYYY-MM-DD)

> `STATUS.md` 只留 active／paused state，history 只增、backlog 只留未結案項目。三種生命週期
> 分開後，不必靠壓縮或人工 pointer 維持可讀性。
>
> 本檔不設 bytes／行數上限；治理靠 stable ID、生命週期與 repo-local audit。

## 關閉與歸檔慣例

- **償還／解決時就關閉**：寫一條 `M-*` milestone record，本檔條目整條移除。
- **變成決策時搬家，不要原地追加**：寫一條 `D-*` decision record，再移除 backlog entry。
- **明確放棄時**：寫一條 `X-*` dead-end record，再移除 backlog entry。
- **stable ID 不重用**：移除後仍由 history record 的 `關聯` 保存原 `B-*`。
- **不刪**未解決的條目。看不順眼不是關閉條件;做掉、或明確放棄並記成決策,才是。

## 技術債

- **B-YYYYMMDD-short-slug · ** [ ] **<債項>**：<影響範圍與償還時機建議>

## 已知缺口

- **B-YYYYMMDD-short-slug · ** <功能面或資料面的已知限制，尚無解決計畫者>
