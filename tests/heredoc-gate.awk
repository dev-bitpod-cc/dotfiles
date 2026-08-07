# heredoc-gate.awk — 找出「不帶引號的 heredoc，body 內含反引號」的寫法。
#
# 為何是 gate 而不只是記憶：bash 對 `<<EOF`（delimiter 未加引號）的 body 會做命令替換，
# 於是文字裡一組行內 code 的反引號會**真的被執行**。2026-08-07 兩次實地：一次讓 `git push`
# 真的推了一條 branch 上 GitHub；一次差點把毀損的 ~/.ssh/config 部署到全機隊（dotfiles-sync
# 用 `<< SSHEOF` 灌 ssh/config，而 ssh/config 正是會長註解的檔案）。
# 兩次的共同點：**寫 Markdown/prose 進檔案**時反引號是標準寫法，所以「幾乎必踩」。
#
# 判準只認一件事：delimiter 沒被引號包住 → **body 字面**出現反引號即紅。
# ⚠ **只管字面，不管展開後的內容**——這不是偷懶，是 shell 的規則：命令替換的結果不會被
# 重新掃描。`$(cat 某檔)` 注入的內容裡即使有反引號也**不會**被執行（2026-08-07 實測確認，
# 當時誤判成同一個地雷、還為它加過一條誤報規則）。所以灌檔用不用 heredoc 都安全，
# 危險的只有「prose 直接寫在 heredoc body 裡」那種。
# quoted heredoc（`<<'EOF'` / `<<"EOF"`）照樣要追蹤進出，否則它的 body 裡若含 `<<X` 樣式的
# 文字（測試 fixture 幾乎一定有），掃描器會以為自己進到一個 unquoted heredoc 而誤報。
# `<<<` 是 herestring，不是 heredoc——靠「match 起點前一字元不是 <」排除。
#
# 用法：awk -f tests/heredoc-gate.awk <檔案...>   命中即逐行印出，無命中則無輸出。

FNR == 1 { in_here = 0; delim = ""; quoted = 0 }
{
    if (in_here) {
        line = $0
        sub(/^[ \t]+/, "", line)          # `<<-` 允許 delimiter 前有 tab 縮排
        if (line == delim) { in_here = 0; next }
        if (!quoted && index($0, "`") > 0)
            printf "%s:%d: unquoted heredoc(<<%s) body 含反引號——會被當命令替換執行\n", \
                FILENAME, FNR, delim
        next
    }
    # 註解行不視為 heredoc 起始：**討論**這個地雷的文字必然寫到 `<<EOF`（本 gate 自己的
    # 註解就是），把它當真會讓後續數行被誤報，而真正的問題行反而落在別處。
    # 已知限制：行尾註解裡的 `<<EOF`（如 `cmd  # 別用 <<EOF`）仍會誤判——罕見，不為它加解析。
    if ($0 ~ /^[ \t]*#/) next
    s = $0
    # `[ \t]*`：bash 允許 `<< EOF`（delimiter 前有空白），漏掉它會讓該 heredoc 整個不被追蹤
    # ——而那不只是漏報：掃描器接著會在它的 body 裡撞到 `<<X` 樣式的**文字**並當成起始，
    # 誤報位置與真正的問題行完全對不上（第一版即如此，RED fixture 反而綠、GREEN 反而紅）
    while (match(s, /<<-?[ \t]*['"]?[A-Za-z_][A-Za-z0-9_]*['"]?/)) {
        pre = substr(s, 1, RSTART - 1)
        # `<<<` 是 herestring：兩道排除——匹配起點前一字元是 `<`（引擎從第二個 `<` 起匹配），
        # 或匹配起點後第三字元是 `<`（從第一個 `<` 起匹配）
        if (substr(pre, length(pre), 1) == "<" || substr(s, RSTART + 2, 1) == "<") {
            s = substr(s, RSTART + RLENGTH)
            continue
        }
        tok = substr(s, RSTART, RLENGTH)
        sub(/^<<-?[ \t]*/, "", tok)
        quoted = (tok ~ /^['"]/)
        gsub(/['"]/, "", tok)
        in_here = 1
        delim = tok
        break
    }
}
