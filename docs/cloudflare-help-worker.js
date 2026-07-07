// Cloudflare Worker — help.bitpod.cc
//
// 用途：忘記 dotfiles 安裝指令時，`curl help.bitpod.cc` 印出正解提醒。
//   純文字（200 text/plain），不做 redirect、不執行任何動作。
//
// 為什麼要獨立端點（不能讓 dot.bitpod.cc 自己回傳這串字）：
//   若 dot.bitpod.cc 回傳指令文字，`curl dot.bitpod.cc | sh` 會把該字串丟給 sh
//   → 又去 curl 同一網址拿到同一串 → 無限套娃且永遠裝不了東西。
//   所以安裝器（dot）與提醒卡（help）必須分開。
//
// 部署：
//   1. Cloudflare 帳戶層級 → Compute (Workers) → Create Worker（先用預設範本 Deploy）
//   2. 進 Worker → Edit code，貼上本檔內容 → Deploy
//   3. Worker → Settings → Domains & Routes → Add → Custom Domain → help.bitpod.cc
//      （自動建好 DNS，不必另外去 DNS 頁加）

export default {
  async fetch() {
    const body =
      "# dotfiles 一鍵安裝（macOS / Linux 自動判斷）：\n" +
      "curl -fsSL dot.bitpod.cc | sh\n";
    return new Response(body, {
      headers: { "content-type": "text/plain; charset=utf-8" },
    });
  },
};
