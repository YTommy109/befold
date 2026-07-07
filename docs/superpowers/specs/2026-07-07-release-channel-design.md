# リリースチャンネル機能

## 概要

リリースを stable と develop の 2 チャンネルに分離する。
一般ユーザーは stable のみ通知を受け、開発者は `defaults` コマンドで
develop チャンネルに切り替えて pre-release の更新通知も受け取れるようにする。

## 変更点

### 1. `AppVersion` のプレリリース対応

`v1.5.0-dev.1` 形式をパースする。

- `-` 前を数値バージョン、後をプレリリース識別子として扱う
- 比較ルール（SemVer 準拠）:
  - `1.5.0` > `1.5.0-dev.2` > `1.5.0-dev.1`
  - プレリリース同士はドット区切りを順に比較（数値は数値として比較）

### 2. `UpdateChannel` enum（新規）

- `stable`（デフォルト）/ `develop`
- `UserDefaults` キー `UpdateChannel` から読み取り
- 切替: `defaults write com.degino.befold UpdateChannel develop`

### 3. `ReleaseFetcher` の拡張

- 既存 `fetchLatest()` はそのまま（stable 用）
- `fetchLatestIncludingPrerelease()` 追加: `/releases` から取得し、
  DMG 付きの最新リリースを返す（develop 用）
- `ReleaseFetching` プロトコルにメソッド追加

### 4. `UpdateChecker` の変更

- コンストラクタに `channel` パラメータ追加
- `stable`: 現行ロジック（`fetchLatest` + DMG チェック）
- `develop`: `fetchLatestIncludingPrerelease` → バージョン比較

### 5. `/release` スキル・`bump.sh` の拡張

- `dev` 引数を追加
- `v{現バージョン}-dev.N`（N は既存タグから自動算出）
- `project.yml` のバージョンは変更しない
- `gh release create --prerelease` で作成
- main ブランチ必須（trunk-based 開発）

### 6. CI（対応済み）

- `release.yml` に `prerelease: ${{ contains(github.ref_name, '-') }}` 追加済み

### 7. `GitHubRelease` モデル（対応済み）

- `hasDMG` プロパティ追加済み
- `UpdateChecker` で DMG 付きリリースのみ更新通知する

## 影響しないもの

- 設定 UI（`defaults` コマンドで切替、開発者のみ）
- `UpdateFlowController`、ダウンロード・インストール処理
- `UpdateCheckCoordinator`（表示ポリシー層）
