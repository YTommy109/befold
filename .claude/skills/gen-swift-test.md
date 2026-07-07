---
name: Generate Swift Test
description: 変更・新規の Swift ファイルに対する Swift Testing テストの不足を検出し、ドラフトを生成する
---

## Generate Swift Test

`BefoldApp/befold/` 配下の変更・新規ファイルについて、対応するテストの有無を確認し、
不足しているテストケースを Swift Testing スタイルでドラフトする。

### 使い方

引数としてファイルパスを受け取る。引数がない場合は `git diff --name-only main...HEAD` で
変更された `.swift` ファイル（`befoldTests/` 配下を除く）を対象にする。

### Steps

1. 対象ファイルを特定する:
   - 引数にファイルパスがあればそれを使う
   - 引数がなければ `git diff --name-only main...HEAD` で変更ファイルを取得し、
     `BefoldApp/befold/` 配下かつ `.swift` のものに絞る
2. 各対象ファイルについて、`query_graph_tool(pattern="tests_for")` でテストが存在するか確認する。
   dagayn が使えない場合は `befoldTests/` 配下でファイル名 + `Tests.swift` の命名規則を grep する。
3. テストが存在しない、またはテストが対象ファイルの公開 API のサブセットしかカバーしていない場合、
   不足しているケースを列挙する。
4. 既存テストファイルのスタイル（`TestSupport.swift` のヘルパー、`@Test("日本語の説明")` の
   表示名規約、`@MainActor` テストの書き方）に合わせてドラフトを生成する。
   - テスト関数名は英語 camelCase（SwiftLint の `identifier_name` 制約）
   - 日本語の説明が必要な場合は `@Test("...")` の表示名に付ける
   - 外部依存（ファイル読込・ネットワーク・ファイル監視）はプロトコル経由のフェイク実装で注入する
     （`InMemoryFileReader.swift` のパターンを参照）
5. ドラフトをユーザーに提示し、承認後に `befoldTests/` 配下へ書き込む。

### 出力フォーマット

```
## <対象ファイル>

### 既存テスト
- <テストファイルパス>（存在する場合）

### 不足しているケース
- <ケース1>: <理由>
- <ケース2>: <理由>

### ドラフト
（Swift Testing コードブロック）
```
