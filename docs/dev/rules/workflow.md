# befold 開発ワークフロー規約

<!-- derived-from ../coding_rule.md -->

メインエージェント向けの開発フロー・コミット・品質チェック・レビュー対応・応答言語の規約。
全体の位置づけは [`../coding_rule.md`](../coding_rule.md) を参照。

## コマンド

```bash
cd BefoldApp
swift build                  # ビルド（SwiftLint も実行される）
swift test                   # テスト（要 Xcode.app）
xcodegen generate            # .xcodeproj を再生成
xcodebuild build -scheme befold  # Xcode ビルド（要 Xcode.app）
npx jest                     # viewer 用 JS（viewer-src/）のテスト
npm run lint:viewer          # viewer-src/ の ESLint（未定義参照の検出）
npm run build:viewer         # viewer-src/ → BefoldKit/Resources/viewer-bundle.js
npm run check:viewer-bundle  # コミット済みバンドルとソースのズレを検出

# コード品質
swift package plugin swiftlint           # SwiftLint を単体実行
swift package plugin --allow-writing-to-package-directory swiftformat  # SwiftFormat 実行
```

## コミット規約

Conventional Commits + 日本語:

```text
<type>: <変更内容を動詞で始める日本語>

[body: 必要な場合のみ]
```

type の選択:

- `feat`: 新機能
- `fix`: バグ修正
- `chore`: ビルド・設定・依存関係
- `docs`: ドキュメントのみ
- `refactor`: 機能変更なしのコード整理
- `test`: テストの追加・修正
- `ci`: CI・リリースワークフロー

## 品質チェック手順

以下を順番に実行する:

1. **SwiftFormat**: `swift package plugin --allow-writing-to-package-directory swiftformat`
2. **Swift ビルド + SwiftLint**: `swift build`（SwiftLint はビルド時に自動実行）
3. **Swift テスト**: `swift test`
4. **JS テスト**: `npx jest`

- **テスト結果をパイプ越しに判定しない**。`swift test | tail -80` の終了コードは `tail` のもので、
  テストが落ちていても 0 になる。グリーンを主張する前に、`set -o pipefail` を有効にするか、
  `swift test > log 2>&1; echo $?` のように**終了コードを明示的に記録**し、あわせて
  `Test run with N tests ... passed` の行を確認する
- 要約行だけを目視する運用も、出力が途中で切れていると見落とす。**終了コードと要約行の両方**
  を根拠にする

すべてパスしたら完了。

## レビュー対応方針

- レビュー・自己チェックで指摘された内容は、同じタスク内で解消する。「次に
  触るときに」と先送りしない
- **「対応必須ではない」「任意」「現状維持でよい」は、実際に代替実装を試して
  比較した後にのみ許される結論である**。試さずに見送りを判断してはならない
- レビュー対象は差分の追加行に限定しない。**編集したファイル内の既存コードに規約違反が
  同居していたら、同じタスク内で是正する**（「今回の変更ではない」を放置の理由にしない）
- レビュー担当は、深刻度が低い指摘であっても「対応不要」の一言で済ませず、
  具体的な代替コードを示す。採用するかどうかの判断は、その代替コードを
  実際に適用・検証した結果に基づく

## 応答言語

- **会話**: ユーザーとのやりとりは基本的に**日本語**で行う
- **説明・コメント**: コード外の説明、コミットメッセージも日本語で書く
- **コード**: 変数名・関数名・ファイル名は英語（Swift API Design Guidelines 準拠）
- ユーザーが英語で質問した場合は、返答も英語で行う
