# befold 開発ガイド

## セットアップ

clone 後に一度だけ実行する（git hooks をインストールする。worktree は
`.git/hooks` を共有するため、以降作成する worktree にも自動的に反映される）:

```bash
bash scripts/setup-git-hooks.sh
```

インストールされるフックは次のとおり。実体は `scripts/` にあり、
`.git/hooks/` 配下には各スクリプトを呼ぶ薄いラッパーだけが置かれる。

| フック | スクリプト | 内容 |
| --- | --- | --- |
| `post-checkout` | `worktree-init.sh` | worktree 作成時の初期化 |
| `pre-commit` | `block-main-commits.sh` | main への直接コミットをブロック（`ALLOW_MAIN_COMMIT=1` で通過） |
| `pre-commit` | `swiftformat-lint.sh` | CI と同じ SwiftFormat チェック |

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
        ├── 同梱アセット（viewer.html / viewer-bundle.js / mermaid.min.js / style.css）
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
（既存ユーザの更新）、`source='archive'` が `/releases` 経由（旧版へ戻した）。
ダッシュボードでは「ダウンロード（LP）」「ダウンロード（自動更新）」
「ダウンロード（旧バージョン）」として連続して並べ、直前に 3 つの和である
「ダウンロード合計」を置く。互いに素な内訳なので、どれか 1 つが「ダウンロード」を
上回って見える並びにしない（TASK-533）。

計測は本文を受け取った要求だけを数える。Hono は HEAD を GET のハンドラへ流すため、
`recordEvent` が HEAD を弾く（TASK-534）。経路ごとの除外にすると、ダウンロード経路を
足すたびに同じ穴が空く。

### 分析ダッシュボードの面構成

<!-- derived-from #配布経路成果物の置き場所 -->

ダッシュボードは目的別に 5 面へ分かれる。面の定義元は `site/src/analytics.ts` の
`DASHBOARD_PAGES` で、ルートの生成・ナビゲーション・クエリ本数の上限テストが
すべてこの配列を読む。

| ルート | 面 | 内容 | クエリ |
|---|---|---|---|
| `/dashboard` | 概要 | 累計 / 本日 / 日毎の推移 / 最新イベント | 4 |
| `/dashboard/users` | 利用者 | 日別ユニークアクセス元 / 稼働バージョン / 時間帯分布 / アップデートの取り込み | 4 |
| `/dashboard/traffic` | 流入 | 内訳 / ページ別 / 言語別 / 人間と自動アクセス | 8 |
| `/dashboard/delivery` | 配信 | 配布ホストと旧経路 / 停止判断の対象経路の日次推移 | 2 |
| `/dashboard/events` | イベント | 人間のアクセスを新しい順に 100 件ずつ（過去へ遡れる） | 1 |

イベント面のページ送りは id を基準にしたカーソル（`?before=` / `?after=`）で、
`OFFSET` は使わない。イベントは常に新しい側へ挿入されるため、オフセットで数えると
ページを送っている間に境界がずれ、同じ行が 2 度出たり抜けたりする。次のページの
有無は上限より 1 件多く引いて同じクエリで確定させる（本数を増やさない）。
概要面の直近 20 件と SSE によるライブ追記はそのまま残し、イベント面は開いた時点の
スナップショットとして SSE に接続しない（過去を見ている最中に先頭へ行が挿さると
読んでいる位置がずれるため）。

1 回の表示で発行する D1 クエリ本数には上限がある（`site/test/query-count.test.ts`）。
上限は**ページごと**と**全ページ合計**の 2 段で、合計にも置くのは「面を増やせば
上限を回避できる」形を防ぐため。この上限の目的は性能ではなく、「指標を 1 つ足す
たびにクエリが 1 本増える」形への退行検知。指標を足すときは、既存クエリへ列を
足すか `UNION ALL` で束ねる。面ごとの実本数はテスト内の `EXPECTED_QUERIES` が
定義元で、上限だけでなく実数も固定してある（枠が空いている面へ黙って 1 本足すと
落ちる）。

**SSE のポーリング 1 周期にも別の上限がある。** 概要面のクエリは「開いたとき
1 回」ではなく、ダッシュボードを開いている間ずっと `POLL_INTERVAL_MS`（30 秒）
ごとに走る。新着が無い周期でもカーソル 2 本（`maxEventId` / `eventsAfter`）を
引くため、タブを 1 つ開いたままにするだけで 4 本/分になる。この重みの違いを面ごとの上限に混ぜない
よう、`MAX_QUERIES_PER_STREAM_CYCLE` を別に立ててある。周期分の D1 アクセスは
`runStreamCycle`（`site/src/routes/dashboard.tsx`）に閉じてあり、テストは
ルートではなくこの関数を呼んで数える。

アップデートの取り込みは 2 つの指標で見る。**確認 → 更新の転換率**は、その日に
アップデート確認を送ったアクセス元のうち、同じ日に更新まで進んだものの割合。分子は
確認と更新の**両方**を持つアクセス元（積集合）で、更新側の数をそのまま分子にすると
率が 100% を超える（同日の確認記録が無い更新が実在する。`visitor_token` が生の
User-Agent を含むため、appcast 取得と DMG 取得で UA が変われば別のアクセス元に
なる）。この取りこぼしは率へ混ぜず別の列に出す。**リリース後の取り込み**は、
タグごとに経過日数別の累積アクセス元数を出す。0 日目は**リリースの公開日ではなく
初回観測日**で、events にも `latest.json` にも公開時刻が無いための代用。公開から
最初のダウンロードまで間があると曲線が速く見える方向にずれる。

**SSE によるライブ更新は概要面だけ。** 他の面は開いた時点のスナップショットで、
その旨を画面に明示する。ライブに見せると、実際には静止している数字を更新中の
ものと読み違える。

集計 SQL は `site/src/analytics.ts` の 1 ファイルに置く。ボット除外条件が 1 箇所に
集約されていることを担保する規約テストが、このファイルのソース文字列を検査する
形になっているため（`site/vitest.config.ts` がこの 1 ファイルだけをテストへ渡す）。
分割すると検査が届かなくなる。

### リリース後の疎通確認（appcast の配信一致）

<!-- derived-from #配布経路成果物の置き場所 -->

Worker が appcast を改変せずに返していることを、**配信の正である R2 のオブジェクト**と
突き合わせて確認する。両チャンネルについて sha256 が完全一致すればよい。

```bash
# stable
npx wrangler r2 object get befold-dist/appcast.xml --remote --pipe | shasum -a 256
curl -fsS https://befold.degino.com/appcast.xml | shasum -a 256

# develop
npx wrangler r2 object get befold-dist/appcast-develop.xml --remote --pipe | shasum -a 256
curl -fsS https://befold.degino.com/appcast-develop.xml | shasum -a 256
```

比較先を GitHub Releases 上の appcast にしてはならない。GitHub 直の appcast は
v1.10.0 以前の配布済みバージョン向けに残しているだけで配信の正ではなく、R2 と
乖離しても一致確認は通ってしまう（v1.10.1 以降のフィード URL は Worker を指す）。

`wrangler` の認証が要る。非対話シェルでは OAuth ログインを開けないため、
`CLOUDFLARE_API_TOKEN` を渡すか、対話的なターミナルで `npx wrangler login` を
済ませてから実行する。

この確認は本番へ実行してよい（`/appcast.xml` への curl は `update_check` として
記録されるが、実配信の検証は記録が走っても意味を持つ確認にあたる）。

## 関連ドキュメント

- [コーディング規約](./coding_rule.md)
- [ネイティブアプリ設計](./native-app-design.md)
