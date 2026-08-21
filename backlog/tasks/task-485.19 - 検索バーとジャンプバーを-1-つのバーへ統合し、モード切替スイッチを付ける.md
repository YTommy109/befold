---
id: TASK-485.19
title: 検索バーとジャンプバーを 1 つのバーへ統合し、モード切替スイッチを付ける
status: In Progress
assignee:
  - '@claude'
created_date: '2026-08-18 15:26'
updated_date: '2026-08-21 09:13'
labels: []
milestone: m-6
dependencies:
  - TASK-485.18
parent_task_id: TASK-485
priority: high
type: feature
ordinal: 766000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

現在、検索バー（`#mmd-find-bar`）と文書内ジャンプバー（`#mmd-jump-bar`）は
別々の DOM・別々のコントローラだが、実質的には既に「1 つのバーの 2 つの状態」に
なっている。

- 排他は `viewer-src/bar.ts` が `openBar: "find" | "jump" | null` という単一の値で
  持っており、別のバーを開くと前を必ず閉じる（TASK-485.1 の設計判断）
- 見た目も共有済み。`viewer.html:59` の `#mmd-jump-bar` は `class="mmd-find-bar"` を
  使い、HTML のコメントに「同時には開かないため見た目・配置のクラスはそのまま共有する」と
  明記されている
- 移動・ハイライトの共通化は TASK-485.12（Done）で `navigation.ts` へ一本化済み

したがって本タスクは状態を増やす変更ではなく、**この排他値をそのまま
「1 つのバーのモード」に読み替える**変更になる。

## やること

1. バーを 1 つに統合し、モード切替スイッチ（検索 / 見出し / 変更箇所）を持たせる
2. モードごとに固有の入力領域だけを差し替える
   （検索: 入力欄 + Aa/ab|/.\* トグル、見出し: レベルトグル、変更箇所: なし）。
   件数表示・前へ/次へ・閉じる・Enter/Shift+Enter・Esc は共通
3. **差分表示モードでバーを開いたときの既定モードを「変更箇所」にする**

## 設計上の分かれ目（着手時に `/review-design` で確定させる）

- **既定モードの適用タイミング。** 「差分なら変更箇所」を適用するのは
  **バーを開く瞬間だけ**にする必要がある。`jump.ts` は再描画のたびに
  `invalidate` → 着地で `refresh` を通るため、そこで既定を再適用すると
  ユーザーが検索モードへ切り替えた直後に黙って引き戻される経路ができる
- **非対応モードの見せ方。** モードごとに capability が違う
  （`ViewerCapabilities.canJump(to:)`、`ViewerCapabilities.swift:103`）。
  無効表示にすると stable ビルドで開発中機能が無効セグメントとして露出する
  TASK-485.8 と同じ形になる。非表示にするとセグメント数が文脈で変わる
- **状態の保持。** 検索クエリ・Aa/ab|/.\* とジャンプのレベル選択を
  モード切替をまたいで保持するか
- **IME。** `ime.ts` の Enter 処理は検索モードにしか関係しないため分岐が要る
- **モード切替のキー割り当て。** 入口が ⌘F 1 本になることで
  `MainMenuBuilder.swift:165` が記録している「⌃⌘ 系が空いていない」問題は
  緩むが、切替そのもののキーは別途決める
- Edit メニューの 2 項目（`DocumentJumpKind.allCases` から生成、
  `MainMenuBuilder.addDocumentJumpItems`）を残すか、モード指定付きの
  「バーを開く」1 系統へ畳むか

## 関連

- TASK-485.18（対象外へ切り替わったらバーを閉じる）は、統合後は
  「モードが失効したら別モードへ落とすか閉じる」に形が変わるため依存で結ぶ
- TASK-485.16（フィーチャーゲート撤去）は、統合後の UI で stable に出したいので
  本タスクに依存させる

## 規模

サブタスク 1 本に収まらない可能性がある。`/review-design` の結果しだいで
分割してよい。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 バーが 1 つに統合され、モード切替スイッチで検索 / 見出し / 変更箇所を切り替えられる
- [ ] #2 差分表示モードでバーを開くと変更箇所モードが既定で選ばれる
- [ ] #3 再描画（ファイル更新・チャンク追記）でユーザーが選んだモードが既定へ引き戻されないことをテストで示している
- [ ] #4 非対応モードの見せ方（非表示 / 無効）と、その選択理由が Implementation Notes に残っている
- [ ] #5 モード切替をまたぐ状態保持の規則が決まり、テストで担保されている
- [ ] #6 件数表示・前へ/次へ・閉じる・Enter/Shift+Enter・Esc がモード間で 1 つの実装を共有している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## /review-design の結論（前提と裏付け）

- canFind（ViewerCapabilities.swift:16,76）・canJump(to:)（ViewerCapabilities.swift:103-108）は
  既に個別の事実ベース判定として存在する（コード参照）。統合後もこれを唯一の真実源として使う。
- FeatureGate.isDocumentJumpEnabled は canJump を丸ごと false にする（ViewerCapabilities.swift:80）。
  TASK-485.18 の可用性伝搬（_mmdApplyJumpAvailability 系）を流用すれば、stable ビルドで
  見出し/変更箇所モードを隠すために新しい gate 信号を JS 側に追加する必要はない
  （未確認: 呼び出しタイミングがバー未オープン時にも届くかは実装時に rg で確認する）。
- Enter/Shift+Enter の受け口は find=入力欄 keydown、jump=document keydown という構造的非対称
  （find.ts:452-467, keyboard.ts:103-114）。統合で必ず手を入れる。
- isRendering フラグは jump 側だけが持つ（jump.ts:96-98）。find は無条件 refresh。
  非アクティブモードは再描画時に計算をスキップし、モード切替時にのみ列挙する方針にする。
- ViewerWindowController 型グループは実測896行（閾値1000）、MainMenuBuilder は377行
  （scripts/check-type-group-size.sh）。Swift側の追加は小さく抑える。

## ユーザー承認済みの製品判断

1. モード切替をまたぐ状態保持: 保持する（検索クエリ・Aa/ab|/.* トグル・見出しレベル選択は
   モード切替では消えない。バーを完全に閉じたときにリセットする）
2. Edit メニューの見出し/変更箇所ジャンプ2項目: 現行のまま残し、実体を
   「統合バーを該当モードへ明示的に切り替えて開く」に差し替える（explicit kind は
   常にそのモードを強制。⌘F 等の非明示オープンだけが showsDiff に応じた既定モードを使う）

## 実装ステップ（短いループで進める。各ステップでテストを通してから次へ）

1. JS: find.ts / jump.ts に重複配線されている件数表示・前後移動・close ボタンの
   クリック配線を共通モジュールへ1箇所化（振る舞い変更なし、リファクタのみ）
2. JS+HTML: viewer.html を単一の #mmd-bar コンテナ + モード切替スイッチ（検索/見出し/変更箇所）
   へ再構成。検索専用の入力欄・トグルは検索モード時のみ、レベルトグルは見出しモード時のみ表示。
   style.css の絶対配置前提（.mmd-find-toggles）を、入力欄を持たないモードと衝突しない形に見直す
3. JS: Enter/Shift+Enter の受け口を統一（検索モードは入力欄 keydown、見出し/変更箇所は
   document keydown のまま存置するか、フォーカス設計を変えて入力欄方式に寄せるかを実装時に確定。
   ime.ts のIME判定はモードごとに正しい経路だけへ結線する）
4. JS: モードの可用性（canFind は常時true、canJump(to:) 由来の availableKinds）に基づき、
   非対応セグメントを非表示にする。TASK-485.18 の closeUnlessAvailable をモード切替スイッチにも
   適用（現在のモードが不可になったら別の利用可能モードへフォールバックするか閉じるかを決める）
5. Swift: WebViewCommandController に openBar(kind: DocumentJumpKind?) 的な単一入口を作る。
   kind が nil（⌘F 相当の非明示オープン）のときだけ showsDiff を見て既定を search/changeBlock に
   分岐。kind 明示時（Editメニュー）は常にそのモードを強制。documentJump(_:) と openFind() を
   この入口へ収斂させる
6. Swift+JS: 状態保持（モード切替をまたぐクエリ・トグル）をユニットテストで固定
7. AC を1つずつ確認し、Definition of Done / 完了処理は task-finalization guide に従う
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
/review-design の結果、実コード（find.ts/jump.ts、計984行、span境界マッチング・isRenderingフラグ等の繊細な不変条件あり）を確認したところ1タスクでのレビュー・検証には大きすぎると判断し、TASK-485.19.1〜.5 へ分割した。分割方針・各サブタスクの担当範囲は各サブタスクのDescriptionに記載。本タスク自身は全サブタスク完了後にfinalizeする。
<!-- SECTION:NOTES:END -->
