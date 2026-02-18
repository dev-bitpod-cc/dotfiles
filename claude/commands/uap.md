依照 CLAUDE.md「文件維護」段落的 protocol 執行：
1. 檢查本次 session 的變更（git diff --name-only + git log --oneline -5）
2. 更新涉及領域的子目錄 CLAUDE.md（crawler/xbrl/risk/scripts）
3. 更新 STATUS.md（如有里程碑）
4. 更新相關 docs/plans/*.md（如有）
5. 更新各文件的 updated 日期
6. git add + commit + push
