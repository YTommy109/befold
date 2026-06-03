# Auto-Upgrade 設計 spec

**日付:** 2026-06-03
**対象ブランチ:** feat/auto_upgrade
**参考実装:** `YTommy109/git-lanes`

---

## 概要

mmdview に自動アップグレード機能を追加する。ユーザーが macOS メニューの「Check for Updates...」を選択するか、アプリ起動時にサイドバーバナーを通じて新バージョンの存在を確認し、DMG をダウンロード・インストールしてアプリを再起動できるようにする。

---

## アーキテクチャ

### コンポーネント構成

```
backend/
  version.py                    # __version__ 定数
  services/
    update_service.py           # GitHub API チェック + ダウンロード管理
    update_installer.py         # DMG マウント・コピー・再起動
    update_mount.py             # hdiutil ラッパー
  routers/
    update.py                   # /api/update/* エンドポイント
  update_window.py              # macOS メニュー統合 (PyObjC)
  templates/
    update_dialog.html          # モーダルダイアログ (400×260)
    partials/
      update_banner.html        # サイドバーフッターバナー
      update_progress.html      # ダウンロード/インストール進捗
      update_idle.html          # アップデートなし時の空 div
```

---

## 各コンポーネントの詳細

### version.py

```python
__version__ = "0.1.0"  # pyproject.toml の version と一致させる
```

`pyproject.toml` の `bumpversion` 設定に `backend/version.py` を追加し、バージョン管理を統一する。

---

### update_service.py

**責務:** GitHub Releases API へのバージョン確認・DMG URL 取得・バックグラウンドダウンロード

**主要関数:**

| 関数 | 説明 |
|------|------|
| `check_update() → dict` | GitHub API で最新バージョンを確認。1 時間 TTL キャッシュ付き |
| `download_update(url: str) → None` | バックグラウンドスレッドで DMG をダウンロード |
| `get_download_state() → dict` | ダウンロード進捗を返す (`idle`/`downloading`/`done`/`error`) |
| `invalidate_cache() → None` | キャッシュをクリアして次回確認を強制する |

**GitHub API エンドポイント:**
`https://api.github.com/repos/YTommy109/mmdview/releases/latest`

**DMG 保存先:**
`~/Downloads/mmdview-update.dmg`

**テスト用環境変数:**
`MMDVIEW_MOCK_DMG=/path/to/dmg` — ダウンロード・マウント全体をモックする

---

### update_installer.py

**責務:** ダウンロード済み DMG からアプリをインストールして再起動する

**処理フロー:**
1. `update_service` から DMG パスを取得
2. `update_mount.mount_dmg()` で DMG をマウント
3. マウントポイント内の `mmdview.app` を検索
4. `/tmp/mmdview-updater.sh` にアップデートスクリプトを書き出す
5. スクリプトをサブプロセスで起動
6. `os._exit(0)` でメインプロセスを即終了

**アップデートスクリプトの処理:**
1. 3 秒待機（アプリの終了を待つ）
2. `/Applications/mmdview.app` を削除
3. DMG 内の `mmdview.app` を `/Applications/` にコピー
4. `hdiutil detach` で DMG をアンマウント
5. DMG ファイルを削除
6. `open /Applications/mmdview.app` でアプリを再起動

**戻り値 (`InstallResult`):**
`"ok"` | `"no_dmg"` | `"mount_failed"` | `"no_app"` | `"not_frozen"`

**テスト用環境変数:**
`MMDVIEW_MOCK_FROZEN=1` — PyInstaller フリーズ済み環境をモックする

---

### update_mount.py

**責務:** hdiutil を使った DMG マウント

**処理:**
1. `xattr -d com.apple.quarantine <dmg>` で検疫属性を削除
2. `hdiutil attach <dmg> -nobrowse -plist` を実行
3. plist 出力をパースしてマウントポイントを返す

---

### routers/update.py

| エンドポイント | メソッド | 説明 |
|---------------|---------|------|
| `/api/update/dialog` | GET | アップデートダイアログ HTML を返す |
| `/api/update/check` | GET | バナー HTML を返す（htmx ポーリング用） |
| `/api/update/download` | POST | ダウンロードを開始し進捗 HTML を返す |
| `/api/update/progress` | GET | 現在のダウンロード進捗を返す（1 秒ポーリング） |
| `/api/update/install` | POST | インストールを実行（成功時はプロセスが終了する） |

---

### update_window.py

**責務:** macOS アプリメニューへの「Check for Updates...」メニュー項目追加

- PyObjC を使って「About」の下にメニュー項目を挿入
- クリック時に `/api/update/dialog` を指す 400×260 モーダル webview を開く
- キャッシュを無効化してから開くことで最新情報を表示する
- 複数ウィンドウの重複起動を防ぐ

---

## UI/テンプレート

### update_dialog.html（モーダル 400×260）

- 現在バージョン vs 最新バージョンを表示
- DMG URL がある場合: 「Download」ボタン
- DMG URL がない場合: GitHub リリースページへのリンク

### partials/update_banner.html（サイドバーフッター）

- 「v{version} があります」という小バナー
- 「Download」ボタン
- `base.html` の `div#update-banner` に埋め込む

### partials/update_progress.html（動的状態）

| `status` | 表示内容 |
|----------|---------|
| `downloading` | プログレスバー（`{percent}%`） |
| `done` | 「ダウンロード完了」+ 「Install & Restart」ボタン |
| `error` | 「ダウンロード失敗」 |
| `install_error:{code}` | 「インストール失敗 ({code})」 |

### partials/update_idle.html

空の `<div>` — アップデートなし時のプレースホルダー

---

## base.html への統合

`base.html` のサイドバーフッターに update バナーを埋め込む:

```html
<div id="update-banner"
     hx-get="/api/update/check"
     hx-trigger="load, focus from:window"
     hx-swap="outerHTML">
</div>
```

ウィンドウフォーカス時に再チェックすることで、ユーザーが他の作業から戻った際にも最新状態を表示する。

---

## データフロー

```
[起動時]
base.html ロード
  → GET /api/update/check (htmx)
  → update_service.check_update()
  → GitHub API (キャッシュ 1 時間)
  → バナー表示 or 空 div

[メニューから手動確認]
「Check for Updates...」クリック
  → update_window.open_update_dialog()
  → キャッシュ無効化
  → モーダル webview を開く
  → GET /api/update/dialog
  → バージョン情報ダイアログ表示

[ダウンロード〜インストール]
「Download」クリック → POST /api/update/download
  → バックグラウンドスレッドで DMG ダウンロード開始
  → GET /api/update/progress (1 秒ポーリング)
  → 完了後「Install & Restart」ボタン表示
「Install & Restart」クリック → POST /api/update/install
  → DMG マウント → .app コピー → updater スクリプト起動
  → os._exit(0) → スクリプトが新バージョンを起動
```

---

## エラーハンドリング

- GitHub API 失敗: `check_update()` は `{available: false}` を返す（クラッシュしない）
- ダウンロード失敗: `status="error"` でユーザーに通知
- インストール失敗: `InstallResult` のエラーコードを UI に表示
- 開発環境（非フリーズ）: `not_frozen` を返しインストールをスキップ

---

## bumpversion への version.py 追加

`pyproject.toml` の `[[tool.bumpversion.files]]` セクションに追加:

```toml
[[tool.bumpversion.files]]
filename = "backend/version.py"
search = '__version__ = "{current_version}"'
replace = '__version__ = "{new_version}"'
```

---

## テスト方針

`tests/unit/` に以下を追加:

- `test_update_service.py`: バージョン比較・キャッシュ・GitHub API モック・ダウンロード進捗
- `test_update_installer.py`: アプリパス検出（フリーズ/非フリーズ）・スクリプト生成・DMG マウント・エラーケース

---

## 対象外（スコープ外）

- Python バックグラウンドスレッドによる独立した定期チェック（htmx の `load` / `focus from:window` トリガーで起動時・ウィンドウフォーカス時の自動確認は実装済み）
- デルタアップデート（差分のみのダウンロード）
- コード署名・公証（Notarization）
- Windows/Linux 対応
