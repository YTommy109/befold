---
name: L10n Check
description: Localizable.xcstrings の en/ja 翻訳漏れ・整合性をチェックする
---

## L10n Check

次の 2 つのカタログの翻訳漏れ・不整合を検出する。**両方を必ず検査する**
（片方だけ見ると、もう片方へ足したキーの検査が空振りする。TASK-632）。

| カタログ | 中身 |
|---|---|
| `BefoldApp/befold/Resources/Localizable.xcstrings` | アプリ本体のメニュー・ダイアログ等 |
| `BefoldApp/BefoldKit/Resources/Localizable.xcstrings` | ビューアー（WKWebView）へ注入する文言 |

### 使い方

引数なし。`git diff` で変更されたキーがあればそれを優先的に確認し、
なければファイル全体を対象にする。

### Steps

1. 上の 2 カタログをそれぞれ読み込み、JSON として解析する
   （`sourceLanguage` は `en`）。以降の検査はカタログごとに行う。
2. 各キー（`strings` オブジェクトの各エントリ）について、`localizations` に
   `en` と `ja` の両方があるかを確認する。
3. 以下を検出する:
   - **翻訳漏れ**: 片方の言語にしか `localizations` がない、または
     `stringUnit.value` が空文字列のキー
   - **`state` が `needs_review` / `translated` 以外**（`new` など未対応状態）のまま
     残っているキー
   - **プレースホルダ不一致**: `%@` `%d` などのフォーマット指定子の個数が
     `en` と `ja` で異なるキー（引数の対応が壊れている可能性）
4. `git diff --name-only` でいずれかの `Localizable.xcstrings` が変更対象に含まれる場合は、
   `git diff` の該当箇所から追加/変更されたキーを特定し、そのキーを優先して報告する。

### 出力フォーマット

```markdown
## L10n Check 結果

### 翻訳漏れ (問題がある場合)
- [<befold | BefoldKit>] `<キー>`: <en のみ / ja のみ / 空文字列>

### プレースホルダ不一致 (問題がある場合)
- [<befold | BefoldKit>] `<キー>`: en=`<検出した指定子>` / ja=`<検出した指定子>`

### 未対応状態のキー (問題がある場合)
- [<befold | BefoldKit>] `<キー>`: state=`<state>`
```

各行の `[...]` はキーが属するカタログ（`BefoldApp/` 直下のターゲット名）。
問題がなければカタログごとに「✅ <befold | BefoldKit>: en/ja の翻訳漏れ・不整合なし（N キー）」と報告する。
