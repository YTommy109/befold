/**
 * 医療費控除のユースケース記事の本文。
 *
 * 素材の出どころ——テンプレートは `site/public/templates/medical-expenses/`、
 * スクリーンショットは `site/public/images/usecase-medical-*.png`（TASK-538.3 が
 * 架空の 4 人家族で手順を一巡させて撮ったもの）。記事に出す数字・氏名・
 * 医療機関名はすべてその架空データのもので、実在しない。
 *
 * **税務の取り扱いを断定しない。** 5 年保存・足切り・対象になる費用は
 * テンプレート側の記述と揃え、最終判断は国税庁と税務署へ送る一文を必ず残す。
 */

import type { FC } from 'hono/jsx'

import type { ArticleLang } from '../lib/articles'
import { T } from './i18n'
import { DOWNLOAD_PATH, REQUIRED_OS } from './shared'

/** 記事に置くスクリーンショット。alt は言語ごとに出し分ける。 */
const SHOTS = {
  tsv: {
    src: '/images/usecase-medical-tsv.png',
    alt: {
      ja: '集計表の TSV が befold で表として表示されている。date・person・provider・amount・receipt の列が並ぶ',
      en: 'The TSV ledger rendered as a table in befold, with date, person, provider, amount and receipt columns',
    },
  },
  receipt: {
    src: '/images/usecase-medical-receipt.png',
    alt: {
      ja: 'スキャンした領収書の PDF が befold でプレビューされている',
      en: 'A scanned receipt PDF previewed in befold',
    },
  },
  readme: {
    src: '/images/usecase-medical-readme.png',
    alt: {
      ja: '運用手順を書いた README.md が befold で表示され、サイドバーにフォルダ構成が並んでいる',
      en: 'The README describing the workflow shown in befold, with the folder tree in the sidebar',
    },
  },
} as const

const Shot: FC<{ lang: ArticleLang; shot: (typeof SHOTS)[keyof typeof SHOTS] }> = ({
  lang,
  shot,
}) => (
  <figure class="article-shots">
    <img src={shot.src} alt={shot.alt[lang]} loading="lazy" width="1512" height="949" />
  </figure>
)

export const MedicalExpensesBody: FC<{ lang: ArticleLang }> = ({ lang }) => (
  <>
    <p>
      <T
        lang={lang}
        ja="領収書をもらったらスマートフォンで撮って投げ込む。それだけで、年末に医療費控除の明細書へ転記できる状態が保たれています。プログラムは 1 行も書いていません。Claude と befold、それとクラウドストレージ上のフォルダ 1 つだけで回している仕組みの記録です。"
        en="Photograph the receipt, drop it in a folder, and by the end of the year the numbers are ready to copy onto a medical expense deduction form. Not one line of code was written for this — it runs on Claude, befold, and a single folder in cloud storage."
      />
    </p>

    <h3>
      <T
        lang={lang}
        ja="家族に渡す説明が 3 行で済む"
        en="What the family has to do fits in three lines"
      />
    </h3>
    <p>
      <T
        lang={lang}
        ja="家族に頼むのはこれだけです。"
        en="This is the entire instruction handed to the rest of the family."
      />
    </p>
    <blockquote>
      <T
        lang={lang}
        ja="病院や薬局の領収書をもらったら、iPhone の「ファイル」アプリで「医療費 Inbox」を開いて、右上の … から「書類をスキャン」。撮って保存するだけ。名前も日付も気にしなくていいし、あとで整理しなくていい。"
        en="When you get a receipt from a clinic or pharmacy, open the “医療費 Inbox” folder in the iPhone Files app and choose “Scan Documents” from the … menu. Take the photo and save. Don’t worry about the filename or the date, and don’t sort anything afterwards."
      />
    </blockquote>
    <p>
      <T
        lang={lang}
        ja="入力フォームは作りませんでした。家族に継続して頼むものは、手数が多いと続かないことが最大のリスクだからです。写真 1 枚なら続きます。命名も整理も、後工程に寄せてあります。"
        en="No input form was built. For anything you have to ask your family to keep doing, the biggest risk is that extra steps make it stop. One photo keeps going. Naming and filing are pushed downstream."
      />
    </p>

    <h3>
      <T
        lang={lang}
        ja="溜めると読めない、都度やると続かない"
        en="Batch it and you can’t read it; do it daily and you stop"
      />
    </h3>
    <p>
      <T
        lang={lang}
        ja="医療費控除は 1 年分の領収書が貯まりますが、集計をするのは年に 1 回だけです。封筒に溜め込むと、年末に日付も金額も読み取れない紙の束と向き合うことになります。かといって、もらうたびに家計簿ソフトへ入力するのは続きません。"
        en="A medical expense deduction covers a whole year of receipts, but you only add them up once. Let them pile up in an envelope and you face an unreadable stack in December. Type each one into a household ledger as it arrives and you quit by March."
      />
    </p>
    <p>
      <T
        lang={lang}
        ja="投入は都度、集計は月に 1 回、確認は人。この 3 つに分けると、どの担当も無理のない量に収まります。"
        en="So the work is split three ways: drop it in as it arrives, collate once a month, and check with human eyes. Each part stays small enough to keep doing."
      />
    </p>

    <h3>
      <T lang={lang} ja="月末に 1 回、こう頼む" en="Once a month, you ask for this" />
    </h3>
    <blockquote>
      <T
        lang={lang}
        ja="Inbox の新しいスキャンを読んで、集計表に追記して、receipts/ にリネームして移して。"
        en="Read the new scans in the inbox, append them to the ledger, then rename and move them into receipts/."
      />
    </blockquote>
    <p>
      <T lang={lang} ja="この 1 行で起きることは次のとおりです。" en="That one line does this:" />
    </p>
    <ol>
      <li>
        <T
          lang={lang}
          ja="Inbox の未処理ファイルから、日付・医療機関・金額・対象者・区分を読み取る"
          en="Read the date, provider, amount, patient and category out of each unprocessed file in the inbox"
        />
      </li>
      <li>
        <T
          lang={lang}
          ja="年 × 人ごとの集計表（TSV）へ日付順に追記する"
          en="Append it to the per-year, per-person TSV ledger, in date order"
        />
      </li>
      <li>
        <T
          lang={lang}
          ja="スキャンを「日付_医療機関名_対象者_金額.pdf」にリネームし、receipts/ の年・人のフォルダへ移す"
          en="Rename the scan to “date_provider_patient_amount.pdf” and move it into the year and person folder under receipts/"
        />
      </li>
      <li>
        <T
          lang={lang}
          ja="読み取れなかった項目や、対象者が判別できないものは報告して確認を取る（推測で埋めない）"
          en="Report anything it could not read, or whose patient is ambiguous, and ask — never fill it in by guessing"
        />
      </li>
    </ol>
    <p>
      <T
        lang={lang}
        ja="読み取りの手順や TSV の仕様は、フォルダの中に置いた README.md と CLAUDE.md に書いてあります。依頼のたびに説明し直す必要はありません。この記事の末尾に、そのまま使えるテンプレートを置いてあります。"
        en="How to read the scans and what the TSV columns mean live in a README.md and CLAUDE.md inside the folder itself, so none of it has to be re-explained each month. The template is linked at the end of this article."
      />
    </p>

    <h3>
      <T lang={lang} ja="読み違いに気づけるのは人だけ" en="Only a person notices a misreading" />
    </h3>
    <p>
      <T
        lang={lang}
        ja="読み取れなかった項目は報告されますが、読み違えたことには気づけません。金額の桁、似た日付、家族の取り違え——ここだけは人が突き合わせます。befold を使うと、その確認が 1 つのウィンドウで済みます。"
        en="It tells you what it could not read. It cannot tell you what it read wrong — a digit in the amount, a similar date, the wrong family member. That part needs a person, and befold keeps the whole check inside one window."
      />
    </p>

    <h4>
      <T
        lang={lang}
        ja="1. 表計算ソフトで開かずに TSV を読む"
        en="1. Read the TSV without a spreadsheet"
      />
    </h4>
    <p>
      <T
        lang={lang}
        ja="集計表はタブ区切りのテキストです。befold で開くと表として並びます。表計算ソフトで開いて保存し直すと、先頭ゼロが落ちたり日付の形式が変わったりすることがあり、次にそのファイルを読むのは LLM なので黙って壊れます。見るのはビューア、直すのは依頼、と分けておくと形式が崩れません。"
        en="The ledger is tab-separated text, and befold lays it out as a table. Open it in a spreadsheet and save it back and a leading zero can vanish or a date format can change — and the next reader of that file is an LLM, so it breaks silently. Read it in a viewer, ask for edits, and the format stays intact."
      />
    </p>
    <Shot lang={lang} shot={SHOTS.tsv} />

    <h4>
      <T
        lang={lang}
        ja="2. 集計表から領収書をすぐ確かめる"
        en="2. Jump from a row to its receipt"
      />
    </h4>
    <p>
      <T
        lang={lang}
        ja="集計表の receipt 列にはファイル名が入っています。サイドバーからその PDF を開いて、金額と日付を原本と突き合わせます。ファイルが直されればウィンドウはその場で更新されるので、開き直す必要はありません。"
        en="Each row carries the receipt’s filename. Open that PDF from the sidebar and compare the amount and date against the original. When a file is corrected the window updates in place — no reopening."
      />
    </p>
    <Shot lang={lang} shot={SHOTS.receipt} />

    <h4>
      <T
        lang={lang}
        ja="3. LLM 向けの規約を、人が読む"
        en="3. Read the rules written for the LLM"
      />
    </h4>
    <p>
      <T
        lang={lang}
        ja="README.md と CLAUDE.md は LLM に読ませるために書いたものですが、仕組みを思い出すのは人のほうです。半年ぶりに「交通費はどう書くんだったか」を確かめるとき、整形された Markdown で読めると速い。"
        en="The README.md and CLAUDE.md are written for the LLM, but the one who forgets how the system works is you. Six months later, when you need to recall how travel costs are recorded, reading it as rendered Markdown is quicker."
      />
    </p>
    <Shot lang={lang} shot={SHOTS.readme} />

    <h3>
      <T lang={lang} ja="持ち帰り: テンプレート" en="Take it with you: the template" />
    </h3>
    <p>
      <T
        lang={lang}
        ja="そのままコピーして使えるものを置いてあります。氏名・医療機関名・住所・電話番号はすべて記入例で、実在のものではありません。この記事のスクリーンショットも同じ架空データで撮っています。"
        en="A copy-and-use template. Every name, clinic, address and phone number in it is a placeholder, and the screenshots in this article use the same fictional data."
      />
    </p>
    <ul>
      <li>
        <a href="/templates/medical-expenses/README.md">README.md</a>
        {' — '}
        <T
          lang={lang}
          ja="フォルダ構成・運用手順・TSV の仕様。唯一の正としてここに集めてある"
          en="Folder layout, the monthly workflow, and the TSV spec — the single source of truth"
        />
      </li>
      <li>
        <a href="/templates/medical-expenses/CLAUDE.md">CLAUDE.md</a>
        {' — '}
        <T
          lang={lang}
          ja="LLM 向けの入口。README を読ませ、推測で埋めないことを求める"
          en="The entry point for the LLM: read the README, and never fill in a value by guessing"
        />
      </li>
    </ul>

    <h3>
      <T lang={lang} ja="知っておくとよいこと" en="Worth knowing" />
    </h3>
    <ul>
      <li>
        <T
          lang={lang}
          ja="スキャンしても紙の領収書は捨てません。医療費控除では領収書の提出・提示は不要になりましたが、自宅で 5 年間保存する義務があります。スキャンは検索と集計のため、紙は保存義務のため、と割り切って両方持ちます。"
          en="Scanning does not let you throw the paper away. Receipts no longer have to be submitted for this deduction, but you must keep them at home for five years. The scan is for searching and adding up; the paper is for the retention rule. You keep both."
        />
      </li>
      <li>
        <T
          lang={lang}
          ja="集計表の区分は明細書の 4 区分（診療・治療／医薬品購入／介護保険サービス／その他の医療費）に合わせてあります。年末にそのまま転記できます。"
          en="The category column matches the four buckets on the deduction form, so the year-end numbers transcribe directly."
        />
      </li>
      <li>
        <T
          lang={lang}
          ja="befold は読むための道具で、編集はできません。直すのは LLM の仕事です。"
          en="befold only reads. Fixing is the LLM’s job."
        />
      </li>
    </ul>

    <p class="listing-note">
      <T
        lang={lang}
        ja="※ この記事は税務のアドバイスではありません。控除の対象になる費用や保存義務の取り扱いは変わることがあります。最終的な判断は国税庁の情報を確認し、迷うものは税務署に問い合わせてください。"
        en="This article is not tax advice. Which costs qualify, and how long you must keep the paperwork, can change. Check the National Tax Agency’s guidance and ask your tax office when in doubt."
      />
    </p>
    <ul class="listing-note">
      <li>
        <a href="https://www.nta.go.jp/taxes/shiraberu/taxanswer/shotoku/1119_qa.htm">
          <T
            lang={lang}
            ja="No.1119 医療費控除に関する手続について｜国税庁"
            en="No.1119 Procedures for the medical expense deduction (National Tax Agency, in Japanese)"
          />
        </a>
      </li>
      <li>
        <a href="https://www.nta.go.jp/taxes/shiraberu/shinkoku/tebiki/2025/06/6_01.htm">
          <T
            lang={lang}
            ja="医療費控除の明細書｜国税庁"
            en="The medical expense deduction statement (National Tax Agency, in Japanese)"
          />
        </a>
      </li>
    </ul>

    <h3>
      <T lang={lang} ja="befold を使ってみる" en="Try befold" />
    </h3>
    <p>
      <a href={DOWNLOAD_PATH} class="btn-primary">
        <T lang={lang} ja="Mac 版をダウンロード" en="Download for Mac" />
      </a>
    </p>
    <p class="listing-note">
      {lang === 'ja' ? (
        <>{REQUIRED_OS.ja}が必要です。無料で使えます。</>
      ) : (
        <>Requires {REQUIRED_OS.en}. Free to use.</>
      )}
    </p>
  </>
)
