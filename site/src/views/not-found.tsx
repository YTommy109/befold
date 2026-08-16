/** ルートにも静的アセットにも当たらなかったときに返すページ（TASK-497）。 */

import type { Context } from 'hono'
import { html, raw } from 'hono/html'
import type { FC } from 'hono/jsx'

import { pathFor } from '../lib/pages'
import { CLEANUP_SCRIPT, REPO_URL, SiteFooter } from './shared'

/**
 * 404 ページ。**日英を 1 枚に併記する。**
 *
 * LP と詳細ページは URL が言語の唯一の持ち主だが（TASK-496）、404 に来るパスは
 * 定義上 `SITE_PAGES` に無く、そこから言語を決められない。`/en` の打ち間違いも
 * `/features` の打ち間違いも同じ経路に来るため、パスの接頭辞で言語を推測すると
 * 半分は外れる。両方書いて、両方の入口へ戻せる形にする。
 *
 * **`PageShell` を使わない。** `PageShell` は canonical・hreflang・og:url・
 * og:locale を `SitePage` から必ず出す。404 は `SITE_PAGES` のエントリを持たず、
 * canonical を出せば存在しない URL を正規化し、hreflang を出せば言語版の対応
 * 関係が壊れる。代わりに `noindex` を付けた最小の head をここに持つ。
 * 意匠（style.css）とフッタと `CLEANUP_SCRIPT` は LP と共有する。
 *
 * **`SiteHeader` も使わない。** 言語切替 nav を `variantsOf(entry.page)` から
 * 描くため `SitePage` が要る。ここでは本文の 2 つのボタンが同じ役割を果たすので、
 * 同じ導線を header と本文に二重に置かない。
 */
export const NotFound: FC = () => (
  <html lang="ja">
    <head>
      <meta charset="UTF-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <title>404 Not Found · befold</title>
      {/* 存在しない URL を検索結果に載せない。canonical は出さない（上の doc を参照）。 */}
      <meta name="robots" content="noindex" />
      <link rel="stylesheet" href="/style.css" />
    </head>
    <body>
      <a class="github-ribbon" href={REPO_URL} target="_blank" rel="noopener" aria-label="GitHub">
        <span>GitHub</span>
      </a>

      <header>
        <h1>befold</h1>
      </header>

      <main>
        <section class="hero">
          <h2>404</h2>
          <p lang="ja">お探しのページは見つかりませんでした。</p>
          <p lang="en">The page you are looking for does not exist.</p>
          <div class="not-found-links">
            <a class="btn-primary" href={pathFor('/', 'ja')} hreflang="ja" lang="ja">
              日本語トップへ
            </a>
            <a class="btn-primary" href={pathFor('/', 'en')} hreflang="en" lang="en">
              English home
            </a>
          </div>
        </section>
      </main>

      <SiteFooter />
      {html`<script>
        ${raw(CLEANUP_SCRIPT)}
      </script>`}
    </body>
  </html>
)

/**
 * 404 ページの応答。ステータスは 404 のまま返す（200 で返して本文だけ 404 に
 * しない——検索エンジンにも `curl` にも「ページがある」と伝わってしまう）。
 *
 * **`recordEvent` は呼ばない。** `events` は LP の指標のための表で、visit として
 * 記録すればページアクセス数に存在しないページが混ざり、新しい kind を足せば
 * 総イベント数の意味が変わる。404 の到達数が要るようになったら Workers
 * Observability で見る（TASK-497 の設計判断 D4）。
 *
 * `Cache-Control: no-store` を付ける。あとでそのパスが実在のページになったとき、
 * 中間キャッシュに残った 404 が返り続けるのを避けるため。
 */
export function notFoundResponse(c: Context): Response | Promise<Response> {
  // 戻り値の型を Response へ狭めない。`c.html` は JSX の解決が非同期になり得る形で
  // 型付けされており、キャストで潰すと Promise をそのまま返す実装が型では通る。
  return c.html(<NotFound />, 404, { 'Cache-Control': 'no-store' })
}
