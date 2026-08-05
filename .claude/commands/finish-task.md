---
description: /finish-task — backlog タスクの検証・完了処理・コミットをまとめて行う
---

# /finish-task — タスクの完了処理

引数: `$ARGUMENTS`（対象タスク ID。例: `TASK-278`。省略時は In Progress のタスクを
`backlog task list --status "In Progress" --plain` で確認し、1 件ならそれを対象にする。
複数あるならユーザーに確認する）

実装が終わったタスクを、検証 → backlog の完了処理 → コミットの順で締める。
各タスクで同じ手順を手で並べると、swiftformat を流し忘れてコミットがフックに
弾かれる・受け入れ条件を証拠なしにチェックする、といった取りこぼしが起きる。

## 手順

### 1. 完了ガイドを読む

```bash
backlog instructions task-finalization
backlog task view $ARGUMENTS --plain
```

受け入れ条件ごとに「何を示せば満たしたと言えるか」を先に決める。実装方針が
起票時と変わっているなら、`backlog task edit $ARGUMENTS --acceptance-criteria ...` で
条件のほうを実態に合わせて書き換える（実装に合わせて条件を緩めるのではなく、
採用した設計で何が保証されるかを書く）。

### 2. テストが空振りしていないか確かめる

新しく追加したテストについて、**修正を一時的に戻すと落ちる**ことを実測する。
対象ファイルはスクラッチパッドへ退避し、確認後に必ず戻す（`git stash` は使わない）。
落ちたテスト名と失敗メッセージを控える。

あわせて、**このタスクで下した設計判断と、前段からの申し送り**を棚卸しする。
粒度・共有範囲・不変条件を決めたなら、それが破れたときに落ちるテストか、
破りようのない構造があるか（doc コメントに書いただけになっていないか）。
前段の Notes に申し送りがあるなら、それが実装で満たされたことを何で示せるか。
根拠は `.claude/CLAUDE.md` の「実装着手前の設計レビュー」（TASK-326 の実測）。

### 3. 整形・テスト・lint・ビルド

```bash
cd BefoldApp
# 整形は機械に決めさせる（swiftformat と swiftlint が衝突する箇所を手で往復しない）
swift package plugin --allow-writing-to-package-directory swiftformat
swift test --skip Integration --skip FileWatcherTests
# 新規ファイルを追加した場合のみ
xcodegen generate
xcodebuild build -scheme befold -destination 'platform=macOS'
```

swiftlint は絶対数では判定できないため、`/swiftlint-baseline` の手順で
origin/main との差分を取り、**新規の警告がゼロ**であることを確認する
（`git archive origin/main` をスクラッチパッドへ展開して比較。`git stash` は使わない）。
既存違反の行数だけが動いた場合は、その旨を実装ノートに書く。

### 4. backlog を締める

```bash
backlog task edit $ARGUMENTS --append-notes "..."   # 採用した方針とその理由、実測値、検証結果
backlog task edit $ARGUMENTS --check-ac 1 --check-ac 2 ...
backlog task edit $ARGUMENTS --final-summary "..." -s Done
```

- Notes には「なぜその設計にしたか」「指摘どおりに直さなかったなら、その理由」
  「実測値（前後の数値・落ちたテスト名）」を残す。
- 満たせなかった受け入れ条件があれば、チェックせずに
  `--comment` で理由を残す（黙って落とさない）。

### 5. コミット

`backlog/tasks/*.md` は git 管理対象なので、実装と同じコミットに含める。
Conventional Commits + 日本語、本文にタスク ID を書く。

直前のコミットと論理的に同じ作業で、まだ push していないなら
`git commit --amend --no-edit` でまとめる。

## 完了報告

次を必ず含める。

- 採用した方針と、単純化の検討結果（指摘や当初案と違う形にしたならその理由）
- 検証の証拠: テスト件数、ビルド結果、swiftlint のベースライン差分、
  「修正を戻すと落ちる」ことの実測
- コミットハッシュと、残っている関連タスク
