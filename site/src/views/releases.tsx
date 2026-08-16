/** 過去の stable バージョンの一覧。最新版に問題があったとき戻る先を示す。 */

import type { FC } from 'hono/jsx'

import { RELEASES_INDEX_URL, type StableRelease } from '../lib/github'
import { jstDayKey } from '../lib/jst'
import { pathFor, type PageLang, type SitePage } from '../lib/pages'
import { T, t, type Localized } from './i18n'
import { REQUIRED_OS } from './shared'
import { PageShell } from './shell'

const PAGE_TITLE: Localized = {
  ja: '過去のバージョン — befold',
  en: 'Previous Versions — befold',
}

const PAGE_DESCRIPTION: Localized = {
  ja: 'befold の過去の安定版を公開日順に並べたページです。最新版で不具合に当たったときは、ここから一つ前のバージョンをダウンロードして戻せます。',
  en: 'Every stable release of befold, newest first. If the latest version has a problem, download an earlier one here and roll back.',
}

/** 旧バージョンの配信ルート。`public.tsx` の登録と対になる。 */
export const ARCHIVE_PREFIX = '/releases'

/** 旧バージョンの DMG を取りに行く URL。計測のため必ず Worker 配下を通す。 */
export function archiveDownloadPath(release: StableRelease): string {
  return `${ARCHIVE_PREFIX}/${release.tag}/${release.dmgFile}`
}

/**
 * 一覧の取得結果。**失敗（null）と 0 件（空配列）を型で分ける。**
 *
 * 同じ「何も出せない」でも、伝えるべきことが違う。取得に失敗したのに
 * 「まだリリースがありません」と出すと、利用者は待っても現れないものを待つ。
 */
export type ReleaseListing = StableRelease[] | null

/**
 * 過去バージョン一覧ページ。
 *
 * 意匠は詳細ページ（features）と同じ枠を使う。表のクラスも共有していて、
 * 見た目の定義は `public/style.css` の 1 箇所にまとまる。
 */
export const Releases: FC<{ origin: string; entry: SitePage; releases: ReleaseListing }> = ({
  origin,
  entry,
  releases,
}) => {
  const lang = entry.lang

  return (
    <PageShell
      origin={origin}
      entry={entry}
      title={t(lang, PAGE_TITLE)}
      description={t(lang, PAGE_DESCRIPTION)}
      ogType="website"
      jsonLd={JSON.stringify({
        '@context': 'https://schema.org',
        '@type': 'CollectionPage',
        name: t(lang, PAGE_TITLE),
        description: t(lang, PAGE_DESCRIPTION),
        url: `${origin}${entry.path}`,
      })}
    >
      <main>
        <nav class="breadcrumb">
          <a href={pathFor('/', lang)}>
            <T lang={lang} ja="← トップページへ戻る" en="← Back to the home page" />
          </a>
        </nav>

        <section class="page-intro">
          {lang === 'ja' ? (
            <>
              <h2>過去のバージョン</h2>
              <p>
                これまでに公開した安定版の一覧です。最新版で不具合に当たったときは、
                ここから一つ前のバージョンに戻せます。動作要件は {REQUIRED_OS.ja} です。
                開発版（dev）は載せていません。
              </p>
            </>
          ) : (
            <>
              <h2>Previous versions</h2>
              <p>
                Every stable release published so far. If the latest version has a problem, roll
                back to an earlier one from here. Requires {REQUIRED_OS.en}. Development (dev)
                builds are not listed.
              </p>
            </>
          )}
        </section>

        <section class="file-types">
          <h3>
            <T lang={lang} ja="安定版の一覧" en="Stable releases" />
          </h3>
          {releases === null ? <ListingUnavailable lang={lang} /> : null}
          {releases !== null && releases.length === 0 ? <ListingEmpty lang={lang} /> : null}
          {releases !== null && releases.length > 0 ? (
            <ReleaseTable lang={lang} releases={releases} />
          ) : null}
          <p class="hero-note">
            <T
              lang={lang}
              ja="さらに古いバージョンと、各版の詳しい変更点は GitHub のリリース一覧にあります: "
              en="Older versions and the full change log for each release are on GitHub: "
            />
            <a href={RELEASES_INDEX_URL}>{RELEASES_INDEX_URL}</a>
          </p>
        </section>
      </main>
    </PageShell>
  )
}

const ReleaseTable: FC<{ lang: PageLang; releases: StableRelease[] }> = ({ lang, releases }) => (
  <div class="table-scroll">
    <table class="file-type-table">
      <thead>
        <tr>
          <th scope="col">
            <T lang={lang} ja="バージョン" en="Version" />
          </th>
          <th scope="col">
            <T lang={lang} ja="公開日" en="Released" />
          </th>
          <th scope="col">
            <T lang={lang} ja="変更点" en="Release notes" />
          </th>
          <th scope="col">
            <T lang={lang} ja="ダウンロード" en="Download" />
          </th>
        </tr>
      </thead>
      <tbody>
        {releases.map((release) => (
          <tr>
            <th scope="row">{release.tag}</th>
            <td>
              <time datetime={release.publishedAt}>
                {jstDayKey(Date.parse(release.publishedAt))}
              </time>
            </td>
            <td>
              <a href={release.notesUrl}>
                <T lang={lang} ja="リリースノート" en="Release notes" />
              </a>
            </td>
            <td>
              <a
                href={archiveDownloadPath(release)}
                aria-label={t(lang, {
                  ja: `${release.tag} をダウンロード`,
                  en: `Download ${release.tag}`,
                })}
              >
                {release.dmgFile}
              </a>
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  </div>
)

/**
 * 一覧を取得できなかったときの表示。**エラーページにはしない。**
 *
 * 旧版へ戻りたい人がここへ来る以上、行き止まりにせず GitHub の一覧へ送る。
 */
const ListingUnavailable: FC<{ lang: PageLang }> = ({ lang }) => (
  <p class="listing-note">
    <T
      lang={lang}
      ja="一覧をいま取得できませんでした。時間をおいて再読み込みするか、下の GitHub のリリース一覧をご覧ください。"
      en="The list could not be retrieved right now. Reload in a moment, or use the GitHub release list below."
    />
  </p>
)

/** 取得はできたが stable が 1 件も無い状態。取得失敗とは別の事実。 */
const ListingEmpty: FC<{ lang: PageLang }> = ({ lang }) => (
  <p class="listing-note">
    <T
      lang={lang}
      ja="公開済みの安定版がまだありません。"
      en="No stable release has been published yet."
    />
  </p>
)
