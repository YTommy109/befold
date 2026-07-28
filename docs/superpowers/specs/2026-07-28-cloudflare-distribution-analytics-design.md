# Cloudflare Workers 配布サイト + 分析ダッシュボード 設計

<!-- supersedes ./../../index.html -->

## 背景

<!-- derived-from #background -->

現状、befold の配布は 2 層構成になっている。

- **紹介 LP**: GitHub Pages（`docs/`, 公開 URL `https://ytommy109.github.io/befold/`）
- **DMG 実体**: 各バージョンタグの GitHub Release（`befold-vX.Y.Z.dmg`）
- **appcast（Sparkle アップデートフィード）**: `appcast` 固定タグの GitHub Release
  - stable: `https://github.com/YTommy109/befold/releases/download/appcast/appcast.xml`
  - develop: `https://github.com/YTommy109/befold/releases/download/appcast/appcast-develop.xml`
  - フィード URL は `BefoldApp/befold/Updates/UpdateChannel.swift` にハードコード（Info.plist の `SUFeedURL` は使わない設計方針）

GitHub Pages は配布に関与せず LP 専用。DMG の署名・公証（notarytool）フローは `.github/workflows/release.yml` が担う。

## 目的

ダウンロード数・アップデートチェック状況・ビジター数をリアルタイムに把握したい。
そのため配布経路を Cloudflare Workers に移し、リクエストが計測層（Worker）を通過する構成にする。
配布ページは公開、分析ダッシュボードは所有者のみ閲覧可能とする。

## スコープ

### 対象

- Cloudflare Worker（Hono / TypeScript）による配布 LP の配信
- ダウンロードリンクの計測リダイレクト（GitHub Releases の DMG へ 302）
- appcast のプロキシ配信（GitHub の appcast を取得して返す＋計測）
- D1（SQLite）へのイベント記録（生 IP 非保持・集計指向）
- Cloudflare Access で保護された分析ダッシュボード
- SSE によるダッシュボードのリアルタイム更新（D1 ポーリング型）

### 対象外

- DMG 実体の R2 移行（GitHub Releases に残す）
- GitHub の署名・公証・リリースワークフロー（`release.yml`）の変更
- 既存 `docs/`（LP）の即時削除（Worker 稼働確認後に別途縮退）

## ディレクトリ構成

monorepo 内に新ディレクトリ `site/` を追加する。

```
site/
├── package.json
├── wrangler.toml            # Cloudflare Worker 設定（D1 バインディング、Access、ルート）
├── tsconfig.json
├── atlas.hcl                # Atlas スキーマ管理設定
├── schema/
│   └── schema.sql           # D1 スキーマ（Atlas が参照する desired state）
├── migrations/              # Atlas 生成のマイグレーション（wrangler d1 migrations で適用）
├── src/
│   ├── index.ts             # Hono エントリ・ルーティング
│   ├── routes/
│   │   ├── public.ts        # GET / , /download , /appcast.xml , /appcast-develop.xml
│   │   └── dashboard.ts     # GET /dashboard , /dashboard/stream（Access 保護）
│   ├── events.ts            # イベント記録（zod 検証 + D1 INSERT, best-effort）
│   ├── analytics.ts         # 集計クエリ（GROUP BY）
│   ├── views/               # Hono JSX による HTML（htmx / hyperscript 埋め込み）
│   └── schema.ts            # zod スキーマ定義
└── test/                    # Vitest + @cloudflare/vitest-pool-workers
```

既存 `docs/` は Worker 稼働確認後に開発ドキュメント専用へ縮退（LP 部分の役割は `site/` へ移る）。

## アーキテクチャ

```
Cloudflare Worker (Hono / TypeScript)  ── site/
  ├── 公開ルート
  │    ├── GET  /                        → 配布 LP（htmx + hyperscript）
  │    ├── GET  /download                → visit/DL をログ→302 で GitHub Releases の DMG へ
  │    ├── GET  /appcast.xml             → update_check をログ→GitHub appcast をプロキシ
  │    └── GET  /appcast-develop.xml     → 同上（develop チャンネル）
  ├── 保護ルート（Cloudflare Access, 所有者メールのみ許可）
  │    ├── GET  /dashboard               → 集計を htmx で描画
  │    └── GET  /dashboard/stream        → SSE（D1 ポーリング型）で新着イベントを push
  └── D1 (SQLite) ── events テーブル（Atlas 管理）
```

データフロー: リクエスト → Worker がイベントを D1 に記録（`ctx.waitUntil` で非同期・best-effort）
→ 本来のレスポンス（リダイレクト / プロキシ / HTML）。

## データモデル（D1 / Atlas 管理）

```sql
-- events: 生 IP は保存しない集計指向テーブル
CREATE TABLE events (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  ts          INTEGER NOT NULL,            -- Unix epoch (ms)
  kind        TEXT    NOT NULL,            -- 'visit' | 'download' | 'update_check'
  version     TEXT,                        -- DL/update 対象バージョン
  channel     TEXT,                        -- 'stable' | 'develop'
  country     TEXT,                        -- CF-IPCountry ヘッダ
  os          TEXT,                        -- UA 要約（macOS バージョン等）
  ua_summary  TEXT,                        -- ブラウザ/クライアント要約
  visitor_day TEXT                         -- sha256(ip + ua + YYYY-MM-DD)：日次ユニーク推定
);
CREATE INDEX idx_events_ts   ON events(ts);
CREATE INDEX idx_events_kind ON events(kind, ts);
```

- **プライバシー**: 生 IP・完全 UA は保存しない。ユニークビジターは
  `sha256(ip + ua + YYYY-MM-DD)` のハッシュのみで推定（IP 復元不可・日次ユニーク）。
- **zod**: イベント形状（`kind` の列挙、必須項目）を検証してから INSERT。
- **集計**: 日別 DL 数・バージョン別内訳・国別・OS 別・update_check 数を `GROUP BY` で都度算出。
  規模的にインデックスで十分。事前集計テーブルは作らない（YAGNI）。

## SSE リアルタイム（D1 ポーリング型）

- `GET /dashboard/stream`（Access 保護）が SSE 接続を保持。
- サーバは 2〜3 秒間隔で `id > lastSeenId` の新着イベントを D1 から取得し、差分を `data:` で push。
- 閲覧者は所有者 1 人のため、ポーリング型で十分なリアルタイム性。Durable Objects は導入しない。
- ダッシュボードは htmx の SSE 拡張（`sse-swap`）で受信し、カウンタ・最新イベント一覧を DOM 差し替え。
  hyperscript で小さな表示制御を行う。

## アクセス制御

- ダッシュボード（`/dashboard`, `/dashboard/stream`）は **Cloudflare Access（Zero Trust）** で保護。
- 所有者のメールアドレスのみ許可する Access ポリシーを設定。Worker 側に認証コードは持たない。
- 公開ルート（LP・download・appcast）は無認証。

## エラー処理・堅牢性

- **計測は best-effort**: D1 INSERT が失敗しても DL リダイレクト / appcast 配信は必ず成功させる。
  `ctx.waitUntil()` でログ書き込みを非同期化し、レスポンスをブロックしない。
- **appcast プロキシ**: 上流（GitHub）取得失敗時はキャッシュ or 502。`Cache-Control` を尊重。
- **旧 appcast 維持**: 既存ユーザーのため GitHub の `appcast` 固定タグはそのまま残す。
  Sparkle フィード URL（`UpdateChannel.swift`）を新 Worker URL へ切替。
  既存ユーザーは次回アップデートチェックで新フィードへ移行する。

## 既存アプリ側の変更

- `BefoldApp/befold/Updates/UpdateChannel.swift` の `feedURLString` を新 Worker の
  appcast URL に変更する（stable / develop 両方）。
- この変更を含むアプリをリリースするまで、旧 URL を見る既存ユーザーは GitHub の appcast を
  引き続き参照する（後方互換）。

## テスト

- Hono ルートハンドラを Vitest + `@cloudflare/vitest-pool-workers` で D1 バインディングごとテスト。
- 検証対象: zod スキーマ、集計クエリ、download リダイレクト、appcast プロキシ、
  イベント記録の best-effort 挙動、visitor_day ハッシュの決定性。
- SSE は接続確立と差分 push の単体検証まで（E2E は手動）。

## 技術スタック

- TypeScript / Hono（Workers ネイティブ、JSX サーバレンダリング）
- htmx + hyperscript（クライアント）
- Cloudflare D1（SQLite）+ Atlas（スキーマ管理・マイグレーション生成）
- zod（イベント検証）
- Cloudflare Access（ダッシュボード認証）
- Wrangler（デプロイ・D1 マイグレーション適用）
- Vitest + @cloudflare/vitest-pool-workers（テスト）

## 段階的移行

1. `site/` の Worker を構築・デプロイ（LP・download・appcast プロキシ・D1・ダッシュボード）。
2. Worker の appcast プロキシが正しく GitHub の appcast を返すことを確認。
3. アプリの Sparkle フィード URL を新 Worker URL へ切替してリリース。
4. LP の参照（README 等）を新 URL へ更新。
5. Worker 安定稼働後、`docs/` の LP 部分を縮退。
