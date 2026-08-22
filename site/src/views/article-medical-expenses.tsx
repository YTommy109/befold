/**
 * 医療費控除のユースケース記事の本文。
 *
 * **現在は骨子だけのドラフト**（`ARTICLES` の該当エントリに `draft: true` が
 * 付いている）。本文は TASK-538.4 で書く。素材は揃っている——テンプレートは
 * `site/public/templates/medical-expenses/`、スクリーンショットは
 * `site/public/images/usecase-medical-*.png`、手順の実測結果は TASK-538.3 の
 * Implementation Notes にある。
 */

import type { FC } from 'hono/jsx'

import type { ArticleLang } from '../lib/articles'
import { T } from './i18n'

/** 記事に置くスクリーンショット。alt は言語ごとに出し分ける。 */
const SHOTS = [
  {
    src: '/images/usecase-medical-tsv.png',
    alt: {
      ja: '集計表の TSV が befold で表として表示されている',
      en: 'A TSV ledger rendered as a table in befold',
    },
  },
  {
    src: '/images/usecase-medical-receipt.png',
    alt: {
      ja: '領収書の PDF が befold でプレビューされている',
      en: 'A receipt PDF previewed in befold',
    },
  },
  {
    src: '/images/usecase-medical-readme.png',
    alt: {
      ja: '運用手順を書いた README.md が befold で表示されている',
      en: 'The README describing the workflow, shown in befold',
    },
  },
] as const

export const MedicalExpensesBody: FC<{ lang: ArticleLang }> = ({ lang }) => (
  <>
    <p>
      <T
        lang={lang}
        ja="スマートフォンで領収書を撮って投げ込むだけで、年末に医療費控除の明細書へ転記できる状態が保たれる——プログラムは 1 行も書かずに、Claude と befold だけで回している仕組みの記録です。"
        en="Photograph a receipt, drop it in a folder, and by the end of the year the numbers are ready to transcribe onto a medical expense deduction form. No program was written for any of this."
      />
    </p>

    <h3>
      <T lang={lang} ja="この記事で書くこと（執筆中）" en="Outline (work in progress)" />
    </h3>
    <ul>
      <li>
        <T
          lang={lang}
          ja="家族に渡す説明が 3 行で済む——手数が多いと続かない"
          en="What the rest of the family has to do fits in three lines"
        />
      </li>
      <li>
        <T
          lang={lang}
          ja="1 年分の領収書は溜めると読めず、都度やると続かない"
          en="Receipts pile up for a year; batching fails, and doing it daily fails too"
        />
      </li>
      <li>
        <T
          lang={lang}
          ja="Inbox に投げる → 月末に依頼する → 集計表に追記されて receipts/ へ移る"
          en="Drop it in the inbox, ask once a month, and it lands in the ledger"
        />
      </li>
      <li>
        <T
          lang={lang}
          ja="befold が効くところ: 表計算ソフトで開かずに TSV を読む／集計表から領収書 PDF をすぐ確かめる／規約文書を人が読む"
          en="Where befold fits: read the TSV without a spreadsheet, jump to the receipt PDF, read the written rules"
        />
      </li>
      <li>
        <T
          lang={lang}
          ja="持ち帰り: テンプレートと、領収書の 5 年保存義務についての注意"
          en="Takeaways: the template, and the five-year receipt retention rule"
        />
      </li>
    </ul>

    <figure class="article-shots">
      {SHOTS.map((shot) => (
        <img src={shot.src} alt={shot.alt[lang]} loading="lazy" width="1512" height="949" />
      ))}
    </figure>

    <h3>
      <T lang={lang} ja="テンプレート" en="Template" />
    </h3>
    <p>
      <T
        lang={lang}
        ja="そのままコピーして使えるものを置いてあります。氏名・医療機関名・住所・電話番号はすべて記入例で、実在のものではありません。"
        en="A copy-and-use template. Every name, clinic, address, and phone number in it is a placeholder."
      />
    </p>
    <ul>
      <li>
        <a href="/templates/medical-expenses/README.md">README.md</a>
      </li>
      <li>
        <a href="/templates/medical-expenses/CLAUDE.md">CLAUDE.md</a>
      </li>
    </ul>

    <p class="listing-note">
      <T
        lang={lang}
        ja="※ 税務の取り扱いは国税庁の情報を確認し、判断に迷うものは税務署に問い合わせてください。"
        en="Check the National Tax Agency's guidance for anything tax-related, and ask your tax office when in doubt."
      />
    </p>
  </>
)
