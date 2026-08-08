# befold 開発ガイド

## セットアップ

clone 後に一度だけ実行する（git hooks をインストールする。worktree は
`.git/hooks` を共有するため、以降作成する worktree にも自動的に反映される）:

```bash
bash scripts/setup-git-hooks.sh
```

## ビルド

### Swift Package Manager

```bash
cd BefoldApp
swift build
swift test
```

### Xcode

```bash
cd BefoldApp
xcodegen generate            # .xcodeproj を生成
xcodebuild build -scheme befold
```

## アーキテクチャ

```text
befold.app (Swift / AppKit + SwiftUI)
  ├── AppDelegate            # ライフサイクル・メニュー・各コーディネータの束ね
  │     ├── ViewerWindowManager    # ウィンドウ生成・管理とセッション記録の更新
  │     ├── SessionRestorer        # 前回セッションのタブ構成の保存/復元
  │     └── UpdateCheckCoordinator # 更新チェックの実行と表示ポリシー
  ├── FileWatcher        # DispatchSource によるファイル監視（0.2s デバウンス）
  ├── ViewerStore        # @Observable 表示状態（content / rejectReason / isTruncated、FileReading + ChunkedTextReading で読込を抽象化）
  └── ViewerWebView      # WKWebView（NSViewRepresentable）
        ├── 同梱アセット（viewer.html / mermaid.min.js / markdown-it.min.js / style.css）
        └── JS ブリッジ: ViewerBridge 経由で evaluateJavaScript("render(content, type)")
```

ファイル変更は `FileWatcher → ViewerStore → evaluateJavaScript` の同一プロセス内伝搬で反映する。

## 技術スタック

- Swift 6 / AppKit + SwiftUI（macOS 14+）
- WKWebView（mermaid.js / markdown-it.js レンダリング）
- DispatchSource（ファイル監視）
- XcodeGen（プロジェクト生成）/ Swift Package Manager（ビルド）

## 更新チャンネル

アプリの更新チェックは stable チャンネル（デフォルト）と develop チャンネルを切り替えられる。

| チャンネル | 対象リリース | 用途 |
|---|---|---|
| `stable` | 正式リリースのみ | 一般ユーザー向け（デフォルト） |
| `develop` | pre-release を含む全リリース | 開発者向け |

### 切り替え方法

```bash
# develop チャンネルに切り替える
defaults write com.degino.befold UpdateChannel develop

# stable に戻す
defaults delete com.degino.befold UpdateChannel
```

### develop リリースの作成

```bash
/release dev
```

現在のバージョン（例: `1.4.8`）に対して `v1.4.8-dev.N` タグを自動で作成する。
N は既存の dev タグから自動算出される。CI が DMG をビルドして GitHub の
pre-release に添付する。

### 配布経路（成果物の置き場所）

<!-- constrained-by ../superpowers/specs/2026-07-28-cloudflare-distribution-analytics-design.md -->

署名・公証は従来どおり GitHub Actions（macOS ランナー）上で行い、**署名済みの
成果物だけ**を Cloudflare R2 へ配置する。Sparkle の EdDSA 秘密鍵と Developer ID
証明書は GitHub Secrets に閉じており、Cloudflare 側には置かない。

| 成果物 | R2 のキー | 配信ルート |
|---|---|---|
| DMG | `releases/<tag>/befold-<tag>.dmg` | `GET /dl/<tag>/<file>`（appcast の enclosure） |
| appcast（stable） | `appcast.xml` | `GET /appcast.xml` |
| appcast（develop） | `appcast-develop.xml` | `GET /appcast-develop.xml` |
| stable の最新ポインタ | `releases/latest.json` | `GET /download`（LP のボタン） |

`release.yml` のステップ順には依存関係がある。**DMG の R2 配置 → appcast 生成 →
appcast の R2 配置**の順を崩さないこと。enclosure が指す実体が R2 に無い状態で
フィードを公開すると、Sparkle が更新に失敗する。R2 への put が失敗したら
ジョブごと落とす（GitHub にだけ置かれた状態を成功として通すと、Worker が
古い成果物を返し続ける）。

GitHub Releases への添付も当面続ける。v1.10.0 以前の配布済みバージョンは
GitHub 直の appcast URL を見ており（フィード URL の Worker 切替は v1.10.1 以降）、
そこからたどれる成果物が必要なため。Worker は R2 に目的のオブジェクトが無いとき
404 ではなく GitHub Releases の同名アセットへ 302 する（Sparkle は enclosure の
404 を更新失敗として扱う）。

必要な GitHub Secrets は `CLOUDFLARE_API_TOKEN`（R2 の書き込み権限を含むこと）と
`CLOUDFLARE_ACCOUNT_ID`。

ダウンロードは発生経路で区別して計測する。`source='lp'` が配布 LP の
`/download` 経由（新規獲得）、`source='sparkle'` が自動アップデート経由
（既存ユーザの更新）。ダッシュボードでは前者を「ダウンロード」、後者を
「自動アップデート適用」として別々に並べる。

## 関連ドキュメント

- [コーディング規約](./coding_rule.md)
- [ネイティブアプリ設計](./native-app-design.md)
