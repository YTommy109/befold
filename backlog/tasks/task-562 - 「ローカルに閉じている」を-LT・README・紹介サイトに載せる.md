---
id: TASK-562
title: 「ローカルに閉じている」を LT・README・紹介サイトに載せる
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-27 15:10'
updated_date: '2026-08-28 01:36'
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

## 追記（2026-08-28）: LP にも節を置いた + 日英の実測

紹介サイトは当初「機能一覧の 1 項目 + FAQ の 1 問」だけだったので、LP の `philosophy` 節（「〜な人へ」の 3 つ目）として「人に見せられない物を読む人へ / 開いた文書は、どこにも行きません。」を追加した。

**日英の掲載状況を実測**（使い捨ての vitest で 4 URL を実際に描画して文字列一致を確認、計測後に削除）:

| | ja | en |
|---|---|---|
| LP の philosophy 節（`/` と `/en`） | ✅ | ✅ |
| 機能一覧の項目（`/features` と `/en/features`） | ✅ | ✅ |
| FAQ（同上） | ✅ | ✅ |

`T` コンポーネントは URL で決まる `lang` に応じて片方だけを描く作りなので、日英いずれかが欠けると該当ページに何も出ない。6 箇所すべて true を確認した。

## 追記（2026-08-28）: 見出しの言い回しを変えた

「ローカルに閉じている」「Stays on Your Machine」は分かりにくい、**「セキュア」「安全」のように一目で分かる語を入れたい**というユーザーの指摘（2026-08-28）。次のとおり変更した。

| 場所 | 変更前 | 変更後 |
|---|---|---|
| 機能一覧（ja） | ローカルに閉じている | 安全に読める（ローカル完結） |
| 機能一覧（en） | Stays on Your Machine | Safe to Open (Local Only) |
| README.md の節 | Stays on your machine | Safe to open — everything stays local |
| README.ja.md の節 | ローカルに閉じている | 安全に読める — ローカル完結 |
| LP の読み手 | 人に見せられない物を読む人へ | 安全に読みたい人へ |

**「セキュアです」と単独では書かない。** 見出しで「安全」と言い、その直後の箇条書き（送らない / 遮断する / 実行しない / 書き換えない）で範囲を限定する構成にしている。本体がサンドボックスでないことも README に残したままで、限定は外していない。

日英とも実際に描画して確認済み（LP・機能一覧の 4 URL）。

## 追記（2026-08-28）: 21 ページを作り直した

「AI が書いたファイル、中に何が入ってるか見てますか?」は**伝えたいことが分からない**というユーザーの指摘。原因は 3 つ。

1. この LT は page 3 で「AI の出力を手直しする」話をしているため、聴衆は「品質のレビューをしていますか?」と読む
2. 脅威（リモート画像・スクリプト・外部通信）がスライド上に 1 語も出てこない。22 へ繋ぐ推論を聴衆が補完する必要があった
3. 他の問いのページは具体物を名指ししている（ソースコード・PDF・CSV）のに、このページだけ抽象的な不安を投げていた

**実物を見せる形へ作り直した。** ターミナル風カード（`.term`）に `design.md` の中身として `![](https://tracker.example.com/p.png?doc=secret-spec)` を出し、URL を `.hot` で目立たせる。補足行は「見た目は画像 1 つ。開いた瞬間、読んだことが相手に伝わります」。これで 22 の「ネットワーク層で遮断」が何を遮断するのかが画で繋がる。

あわせて `.note` を `clamp(13px, 2.2vmin, 22px)` → `clamp(14px, 2.6vmin, 26px)` へ拡大（18 / 21 / 24 の補足行がプロジェクターで読めるように）。befold で描画して目視確認済み。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
「文書が外に出ない」性質を LT スライド（問い + 答えの 2 枚、全体を 24 ページへ振り直し）・README の新節・紹介サイトの機能一覧と FAQ（日英）に載せた。主張はすべてコードで裏を取り、サンドボックス済み・一切通信しない等の言えない主張は載せていない。site の vitest 431 件・lint・format・markdownlint すべて通過。
<!-- SECTION:FINAL_SUMMARY:END -->
