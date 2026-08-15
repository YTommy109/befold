---
id: TASK-476.4
title: アプリ本体の公開サイト URL と Sparkle フィード URL を新ドメインへ切り替える
status: Done
assignee:
  - '@claude'
created_date: '2026-08-13 14:21'
updated_date: '2026-08-14 07:08'
labels:
  - site
dependencies:
  - TASK-476.1
  - TASK-476.2
parent_task_id: TASK-476
priority: high
type: chore
ordinal: 101400
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
アプリからサイトを指す URL を新ドメインへ更新する。ADR 0007 の決定 3 で「切り替える」と確定済み。

<!-- constrained-by ../../docs/adr/0007-distribution-site-custom-domain.md -->

対象（実測）:
- `BefoldApp/BefoldKit/AppLinks.swift:10,15` の homepage（?ref=about）/ help（?ref=help）
- `BefoldApp/befold/Updates/UpdateChannel.swift:21,23` の appcast / appcast-develop
- 対応するテスト `AppLinksTests.swift:12,24` / `UpdateChannelTests.swift:30,36`（いずれもホストを固定値で期待している）

注意点:
- Sparkle のフィード URL 変更が効くのは、この変更を含むバージョンをインストールしたユーザーのみ。旧ホストへのアクセスは永続するため、**旧ホストの appcast 配信を止める前提の実装をしない**。
- 切り替える理由は可搬性（独自ドメインは DNS で向き先を差し替えられるが `*.workers.dev` は Cloudflare アカウントに固定される）。「旧ホストを止められるようになるから」ではない — ADR 0007 の決定 1 で旧ホストは恒久維持と決めている。
- `?ref=` の値は既存の集計軸と互換を保つ（値を変えると過去データと接続できない）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 AppLinks の homepage / help が befold.degino.com を指し、?ref= の値は従来のまま
- [x] #2 appcast / appcast-develop の URL が befold.degino.com へ更新され、UpdateChannelTests が新 URL を検証している
- [x] #3 更新チェックが新 URL で実際に動作することを dev ビルドで確認し、結果を Implementation Notes に記録している
- [x] #4 旧ホストの appcast も同時に 200 を返し続けることを確認している（切り替えが旧経路を壊していない）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. AppLinks に配布サイトのオリジン定数を置き、ホスト名リテラルを Swift 側でも 1 箇所に畳む（ADR 0007 の決定 6 と同じ理由。現状 4 箇所に散っている）
2. AppLinks.homepage / help をその定数から組む。?ref=about / ?ref=help の値は変えない（過去データと接続できなくなるため）
3. UpdateChannel.feedURLString を同じ定数から組む。Sparkle のフィード URL は Info.plist ではなく SPUUpdaterDelegate.feedURLString(for:) 経由なので、変更箇所はこの 1 つ（実測: grep で SUFeedURL のヒットなし）
4. AppLinksTests / UpdateChannelTests の固定値を新ドメインへ更新する
5. swift test を回す。dev ビルドを作って更新チェックが新 URL で動くことを実機確認する
6. 旧ホストの appcast が引き続き 200 を返すことを確認する

## /review-design を回さない理由

CLAUDE.md の「実装着手前の設計レビュー」は、新しい状態・述語・表示設定を足す変更、値の持ち方を変える変更、既存の不変条件・共通経路に触る変更を対象にしている。本タスクはリテラル URL の差し替えと、その 4 箇所を 1 箇所へ畳む変更で、状態も述語も経路も増えない。TASK-476.3 で site 側の同じ論点（ホスト名リテラルを散らさない）は設計レビュー済み。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 変更したもの

- `BefoldApp/BefoldKit/AppLinks.swift`: `siteOrigin = "https://befold.degino.com"` を追加し、`homepage` / `help` をそこから組む形にした。`?ref=about` / `?ref=help` の値は変えていない
- `BefoldApp/befold/Updates/UpdateChannel.swift`: `import BefoldKit` を足し、`feedURLString` を `AppLinks.siteOrigin` から組む
- `BefoldApp/befoldTests/AppLinksTests.swift` / `UpdateChannelTests.swift`: 期待値を新ドメインへ更新

ホスト名リテラルを 4 箇所から 1 箇所へ畳んだ。散っていると、次にホストが変わったときに About のリンクだけ直って更新経路が取り残される（ADR 0007 の決定 6 が配布サイト側に置いた規定を、アプリ側にも同じ理由で適用した）。

## Sparkle への受け渡し経路（実測）

`SUFeedURL` は Info.plist にも project.yml にも存在しない（`grep -rn "SUFeedURL" BefoldApp` のヒット 0 件）。フィード URL は `AppUpdaterController.feedURLString(for:)`（`SPUUpdaterDelegate`）が `UpdateChannel.read(from:).feedURLString` を返す経路だけで渡る。したがって変更点は `UpdateChannel.feedURLString` の 1 箇所で足りる。

## AC #3 の実機確認

Debug ビルド（`xcodegen generate` → `xcodebuild build -scheme befold -configuration Debug`）を起動し、メニュー「befold > アップデートを確認…」を System Events からクリックした。Worker の observability ログで、実際に届いたリクエストを確認した。

| 時刻 (UTC) | チャンネル | Worker が受けた URL | ステータス |
|---|---|---|---|
| 2026-08-14T07:03:10 | develop | `https://befold.degino.com/appcast-develop.xml` | 200 |
| 2026-08-14T07:03:58 | stable | `https://befold.degino.com/appcast.xml` | 200 |

いずれも script version `81b68af8`（TASK-476.3 のデプロイ）。チャンネルは `defaults write com.degino.befold UpdateChannel` で切り替えて両方を測り、確認後 develop へ戻した。

appcast の中身が Sparkle の読める形であることも確認した（`Content-Type: application/xml; charset=utf-8`、`xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"`、`<sparkle:version>1519</sparkle:version>`）。

**注意**: observability のログ取り込みには数十秒の遅れがある。クリック直後に問い合わせると空が返るため、結果が無いことをもって「リクエストが飛んでいない」と判断しない（実際 1 回目の問い合わせは空で、40 秒後の再問い合わせで同じイベントが出た）。

## AC #4 の確認

旧ホストの `https://befold.tommy109.workers.dev/appcast.xml` と `/appcast-develop.xml` はどちらも 200。`/appcast.xml` は新ドメインと `diff` で内容一致。切り替えは旧経路を壊していない。

## 品質チェック

- `swift build` 成功、`swift test` 1504 件 / 238 スイート パス
- swiftlint: main のベースラインと差分ゼロ（どちらも 54 件。`git archive origin/main` で別ディレクトリへ展開して比較、行番号は正規化）
- swiftformat: 全ターゲットで `0/N files require formatting`（pre-commit フックで実行）

## 未対応（別タスク）

`.github/workflows/release.yml:274` の `download_url_prefix` は TASK-476.5 の AC #1 の対象なので、ここでは触っていない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
AppLinks に siteOrigin を置いてアプリ側のホスト名リテラルを 1 箇所へ畳み、homepage / help / appcast / appcast-develop を befold.degino.com へ切り替えた。?ref=about / ?ref=help の値は変えていない。Sparkle への受け渡しは Info.plist の SUFeedURL ではなく SPUUpdaterDelegate 経由であることを grep で確認し（SUFeedURL のヒット 0 件）、変更点が UpdateChannel.feedURLString の 1 箇所で足りることを裏付けた。Debug ビルドを起動してメニューから更新チェックを実行し、Worker の observability ログで stable が /appcast.xml、develop が /appcast-develop.xml をどちらも新ドメインで 200 で取得したことを実測した。旧ホストの appcast も同時に 200 で、新ドメインと内容一致。swift test 1504 件パス、swiftlint は main とのベースライン差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
