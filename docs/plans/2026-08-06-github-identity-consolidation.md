# GitHub 多身分收斂——讓標準 URL 直接可用

> **spec 定稿**（2026-08-06 記錄，未開工）。**寫後不改** —— 定稿存於此，進度與下一步留在
> `STATUS.md`「進行中」。存放位置依 `~/.claude/skills/project/references/dossier.md` 的檔案
> 分工表：`docs/plans/*.md` = 帶日期的設計文件（spec 定稿），STATUS.md = 就地演化的常駐檔。

**Context**:krepo 拆出 `krepo-common` 後,依賴要寫成 git URL。原本沿用本家的
`git@github-work:...`,但 **`github-work` 是本機 SSH alias、不是真實主機名**——寫進 repo
等於要求每個消費者的機器都有同名 alias,而接手者撞到的會是一個「看起來像網路錯誤、
實際上是少了一段 SSH 設定」的失敗。krepo 端已改標準 `git@github.com:`(已 ship),
但**機器端的多身分配置還沒收斂**,現在靠 `insteadOf` 撐著,那是多加一層改寫機制、不是簡化。

**Goal**:標準 URL(`git@github.com:`)在每台機器上都直接可用,`insteadOf` 整層移除。

**現況盤點**(2026-08-06 實測):

| 機器 | `github-work` | 個人(`github.com`) |
|---|---:|---|
| 工作 mac | **28** | **2**(`isdotgd`、`.dotfiles`) |
| db01 | 全部 | **0** |
| 個人 MacBook | 也有工作 repo | 少數幾個 |

**關鍵事實:三台機器的主要身分都是「工作」**——個人 MacBook 上也處理工作 repo,
而公司開發機不會 clone 個人 repo。所以**沒有機器差異**,不需要 host-local 覆蓋
(`ssh/config` 的 `Include ~/.ssh/config.local` 機制留著備用即可)。

**方案**(共用設定,三台一致):

```
# 工作帳號 (jjshen-eland) = 預設 = 標準寫法
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_github_work
    AddKeysToAgent yes
    IdentitiesOnly yes

# 私人帳號,少數 repo 明示
Host github-me
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_github
    AddKeysToAgent yes
    IdentitiesOnly yes
```

⚠️ **`IdentitiesOnly yes` 一行都不能少**(現行兩個 block 本來就有,照抄即可)。少了它,
ssh 會把 agent 裡的 key **逐一送給 GitHub**,而 GitHub 接受第一把有效的——於是認到**錯誤
帳號**。這會直接打掉 AC 1 與 AC 5,且**失敗長相是「連得上但權限不對」**,比連不上更難查
(連不上至少當場知道)。同理 `User git` 與 `HostName` 也照現行寫法保留,不要只留 IdentityFile。

- **`github-work` 整條刪除**——`github.com` 就是工作,不需要第二條路徑
- 工作 repo 的 remote 全部改標準 `git@github.com:`(機械替換,見下)
- 個人 repo 改 `git@github-me:`(工作 mac 只有 2 個)
- **移除 mac 與 db01 的 `insteadOf`**(2026-08-06 為了讓 krepo 能拉依賴而暫設在各自的
  `~/.gitconfig`;它們是這次收斂要消滅的對象,不是終態)

剩下的唯一 alias 是 `github-me`,**不可約**——GitHub 一把 SSH key 只能綁一個帳號,
兩個身分就必須有一種區分方式。

**AC**:

1. 三台機器上 `git clone git@github.com:elandcomtw/...` 直接成功,無 URL 改寫
2. `gh repo clone` 也對(⚠️ **`gh` 完全不看 SSH alias**,這是 alias 方案永遠解不掉的一半,
   只有「讓 `github.com` 就是工作身分」能解)
3. `~/.gitconfig` 內無任何 `insteadOf`,`ssh/config` 內無 `github-work`
4. 三台機器上 `cd ~/Projects/krepo && uv sync` 都能拉到 `krepo-common`
5. 個人 repo(`isdotgd`、`dotfiles`)在改用 `github-me` 後仍可 push

**遷移順序**(順序錯會鎖住存取):

```bash
# 1. 先確認每台機器都有 ~/.ssh/id_github_work（個人 MacBook 也要，它也跑工作 repo）
# 2. 改 dotfiles 的 ssh/config，部署到各機器，驗證身分：
#    ssh -T git@github.com   → 應認到 jjshen-eland
#    ssh -T git@github-me    → 應認到 dev-bitpod-cc
#    ⚠️ 判準是「認到誰」不是「連得上」。認到錯帳號 → 八成是 IdentitiesOnly 沒設，
#       ssh 把 agent 裡的 key 逐一送出、GitHub 收了第一把有效的。
# 3. 身分驗證通過後才改 remote（第 2 步沒過就往下做，會把 remote 改成連不對身分的形式）：
for d in ~/Projects/*/ ~/.dotfiles; do
  url=$(git -C "$d" remote get-url origin 2>/dev/null) || continue
  case "$url" in
    git@github-work:*) git -C "$d" remote set-url origin "${url/github-work:/github.com:}" ;;
    git@github.com:dev-bitpod-cc/*) git -C "$d" remote set-url origin "${url/github.com:/github-me:}" ;;
  esac
done
# 4. 最後移除 insteadOf：git config --global --unset-all url.<...>.insteadOf
```

⚠️ **`.dotfiles` 自己的 remote 也要改**(它是個人 repo)——上面的迴圈已涵蓋,但要記得
那正是你正在編輯的 repo,改完先 `git remote -v` 確認再 push。

**風險與回退**:動的是憑證設定,改錯會讓所有 repo 存取一起失敗。回退指令**依「改動是否已
commit」分兩種**——`git checkout ssh/config` 只在**尚未 commit** 時有效;遷移一旦 commit
(而跨機部署的前提就是 commit + push),它從 HEAD 取回的還是新版,等於把壞設定又還原一次:

```bash
git revert <遷移 commit>                      # 已 commit(跨機部署後的常態)
git checkout <遷移前 commit> -- ssh/config    # 或只取回單檔
git checkout ssh/config                       # 僅限尚未 commit
```

⚠️ **但部署後才生效**——回退也要重新部署,別以為 git 操作完就完事了。

⚠️ **回退路徑本身會被這個變更弄壞**:遠端機器拉 dotfiles 走的正是 GitHub SSH。認證改壞又
已散佈出去,那些機器就**拉不到修正**——得 `ssh <host>`(內網 CA cert,不受此變更影響)進去
手動改 `~/.ssh/config`,或臨時加回 `insteadOf` 撐住。**先在一台機器驗過再散佈,不要一次
`dotsync` 全部。建議清醒時做,不要在深夜動**。
