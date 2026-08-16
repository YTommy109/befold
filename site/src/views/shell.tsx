/** 全ページ共通の HTML 骨格。言語に依存するメタ情報を 1 箇所で組む。 */

import type { FC, PropsWithChildren } from 'hono/jsx'
import { html, raw } from 'hono/html'
import { OG_LOCALE, variantsOf, type SitePage } from '../lib/pages'
import { CLEANUP_SCRIPT, SiteFooter, SiteHeader } from './shared'

/**
 * `<html>` から `<body>` までを組み立てる。
 *
 * canonical・hreflang・og:url・og:locale・`<html lang>` は、どれも「いまどの
 * バリアントを配信しているか」から決まる。ページごとに書くと 4 ページ × 5 項目の
 * 同期が要り、片側だけ直った状態がテストを通ってしまうため、`entry` 1 つから
 * 全部を導く形にしてここへ寄せた。
 */
export const PageShell: FC<
  PropsWithChildren<{
    origin: string
    entry: SitePage
    title: string
    description: string
    ogType: 'website' | 'article'
    imageAlt?: string
    jsonLd: string
  }>
> = ({ origin, entry, title, description, ogType, imageAlt, jsonLd, children }) => (
  <html lang={entry.lang}>
    <head>
      <meta charset="UTF-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <title>{title}</title>
      <meta name="description" content={description} />
      <link rel="canonical" href={`${origin}${entry.path}`} />
      {/* 自己参照を含む全バリアントを列挙する。検索エンジンは「各版が自分自身を
          含む全版を相互に指す」ことを対応関係の成立条件にしているため、自分への
          alternate を省くと対応が成立しない。x-default は置かない——Accept-Language
          で振り分ける入口ページを作っていないので、指すべき既定版が無い。 */}
      {variantsOf(entry.page).map((variant) => (
        <link rel="alternate" hreflang={variant.lang} href={`${origin}${variant.path}`} />
      ))}
      <meta property="og:type" content={ogType} />
      <meta property="og:site_name" content="befold" />
      <meta property="og:title" content={title} />
      <meta property="og:description" content={description} />
      <meta property="og:url" content={`${origin}${entry.path}`} />
      <meta property="og:locale" content={OG_LOCALE[entry.lang]} />
      {variantsOf(entry.page)
        .filter((variant) => variant.lang !== entry.lang)
        .map((variant) => (
          <meta property="og:locale:alternate" content={OG_LOCALE[variant.lang]} />
        ))}
      {/* og:image は言語別に用意しない。本文テキストを含まないスクリーンショット
          由来の画像なので、1 枚で両言語に使える。 */}
      <meta property="og:image" content={`${origin}/images/ogp.png`} />
      <meta property="og:image:width" content="1200" />
      <meta property="og:image:height" content="630" />
      {imageAlt === undefined ? null : <meta property="og:image:alt" content={imageAlt} />}
      <meta name="twitter:card" content="summary_large_image" />
      <link rel="stylesheet" href="/style.css" />
      {html`<script type="application/ld+json">
        ${raw(jsonLd)}
      </script>`}
    </head>
    <body>
      <SiteHeader title="befold" entry={entry} />
      {children}
      <SiteFooter />
      {html`<script>
        ${raw(CLEANUP_SCRIPT)}
      </script>`}
    </body>
  </html>
)
