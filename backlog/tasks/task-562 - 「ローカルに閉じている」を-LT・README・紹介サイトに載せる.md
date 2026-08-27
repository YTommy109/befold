---
id: TASK-562
title: 「ローカルに閉じている」を LT・README・紹介サイトに載せる
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-27 15:10'
updated_date: '2026-08-27 15:15'
labels: []
dependencies: []
priority: medium
type: docs
ordinal: 812000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
befold の「文書が外に出ない」性質を、実装で裏の取れた範囲だけ切り出して 3 箇所に載せる（ユーザー判断、2026-08-28）。

## 載せる主張（すべてコードで確認済み）

- 文書の中身・ファイル名・パスを送る経路が無い。アプリが出す通信は Sparkle のアップデート確認（appcast の GET）だけ（`AppUpdaterController`。Swift 側に `URLSession` の使用箇所なし）
- 逆方向も塞ぐ。`RemoteLoadBlocker` が `WKContentRuleList` で `^https?://` と `^wss?://` を種別を問わずブロックするので、文書に埋め込まれたリモート画像・トラッキング画像・外部スクリプトは読み込まれない
- 直接 HTML モードでは JS が無効（`DirectHTMLModeController.enter` が `allowsContentJavaScript = false`）。Markdown は DOMPurify + `script-src 'self'`
- 開いたファイルを書き換えない。git 連携は読み取りのみでフックも走らない

## 載せない主張

- 「サンドボックス済み」— 本体の entitlements は空で App Sandbox は**無効**（有効なのは QuickLook 拡張のみ）
- 「一切通信しない」— アップデート確認があり、配布サイト側でその取得が計測されている
- 「CSP で外部画像を止めている」— file:// では `img-src` が効かない（TASK-526 の実測）

## 載せ先

1. LT スライド（`sample/presentation/`）: CLI のページの後ろに問い + 答えの 2 枚
2. `README.md`: Why befold の直後に節を 1 つ
3. 紹介サイト: 機能一覧の項目と FAQ の 1 問（ja/en 両方）
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 LT スライドに問い + 答えの 2 枚が入り、通し番号と進捗バーが振り直されている
- [x] #2 README.md に節があり、載せない主張が混ざっていない
- [x] #3 紹介サイトの機能一覧と FAQ に日英で載っている
- [x] #4 site の vitest / lint / format が通る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## LT スライド

CLI（20）の後ろに 2 枚を挿入し、全体を 22 → 24 ページへ振り直した（ノンブル・`.progress.pNN` クラス・style.css の幅ルール）。

- 21: 「AI が書いたファイル、中に何が入ってるか **見てますか?**」
- 22: 「**外に出ません。**」+ 3 点（送らない / 遮断する / 書き換えない）+ 「このスライドも befold で開いている HTML — JS ゼロ・外部参照ゼロ」

箇条書き用に `.points` を style.css へ追加（プロジェクター前提で `clamp(15px, 3vmin, 32px)`）。**このページで語る内容とデッキ自身の作りが一致している**ことが売りなので、CSP 宣言（TASK-561）と JS ゼロは崩さない。

## README.md

Why befold の直後に "Stays on your machine" の節を追加。4 点（送らない / 文書からも出さない / スクリプトを実行しない / 書き換えない）と、署名・notarize・Ed25519 に触れ、**「本体はサンドボックスではない（サンドボックスなのは QuickLook 拡張）」ことも明記**した。都合の良い部分だけを書かない。

## 紹介サイト

- `site/src/views/shared.tsx` の `MORE_FEATURES` に「ローカルに閉じている / Stays on Your Machine」を追加（機能一覧は features 面がこの配列を描くので、追加はここ 1 箇所）
- `site/src/views/features.tsx` の `FAQ` に「開いたファイルの内容が外部へ送られることはありますか？」を追加。編集可否の質問の前に置いた（読むだけ → 送らない、の並び）

## 実測

- `npm test`（site）: 13 files / 431 tests 通過。`npm run lint`（--type-aware）・`format:check`・`markdownlint-cli2` すべてゼロ件
- 新しい 2 枚を befold で開いて撮影し、目視確認（ノンブル 21/24・22/24、進捗バー、箇条書きの可読性）

## 併せて直したもの

`sample/presentation/README.md` の送り方の記述（「ツールバーの ← → で次のファイルへ」）が誤りだったので直した。**この訂正は一度 PR #603 で出したがクローズしたため main に入っておらず、ここで入れ直している。**

## 追記（2026-08-28）: 日本語 README への反映漏れ

`README.md` にだけ節を足し、対になっている `README.ja.md` を落としていた（ユーザーの指摘で発覚）。同じ位置・同じ 4 点・同じ但し書き（本体はサンドボックスではない）で「ローカルに閉じている」を追加し、両者の `##` 見出しが 1 対 1・同順で並ぶことを確認した。

**この 2 ファイルは対で更新する**という関係がリポジトリのどこにも書かれておらず、機械的な検査も無い。同じ落とし方が次も起きうる。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
「文書が外に出ない」性質を LT スライド（問い + 答えの 2 枚、全体を 24 ページへ振り直し）・README の新節・紹介サイトの機能一覧と FAQ（日英）に載せた。主張はすべてコードで裏を取り、サンドボックス済み・一切通信しない等の言えない主張は載せていない。site の vitest 431 件・lint・format・markdownlint すべて通過。
<!-- SECTION:FINAL_SUMMARY:END -->
