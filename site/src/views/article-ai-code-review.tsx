/**
 * 「AI が書いた変更を差分表示でレビューする」記事の本文。
 *
 * **現在はドラフト**（`ARTICLES` の該当エントリに `draft: true`）。公開前に決めることが
 * 2 つある——(1) TASK-537（git 管理外で「変更のあるファイルのみ」が押せてしまう）を
 * 直す、(2) スクリーンショットのメニューが英語表記なので、日本語 UI で撮り直すか
 * そのまま使うかを決める。
 */

import type { FC } from 'hono/jsx'

import type { ArticleLang } from '../lib/articles'
import { T } from './i18n'

/** 記事に置くスクリーンショット。alt は言語ごとに出し分ける。 */
const SHOTS = {
  allFiles: {
    src: '/images/usecase-review-all-files.png',
    alt: {
      ja: 'サイドバーにフォルダ内の全 11 ファイルが並び、変更されたものにバッジが付いている',
      en: 'The sidebar lists all 11 files in the folder, with badges on the changed ones',
    },
  },
  changedOnly: {
    src: '/images/usecase-review-changed-only.png',
    alt: {
      ja: '同じフォルダが変更のある 4 ファイルだけに絞り込まれ、本文側に差分が出ている',
      en: 'The same folder filtered down to the four changed files, with a diff in the main pane',
    },
  },
  diff: {
    src: '/images/usecase-review-diff.png',
    alt: {
      ja: 'Markdown ファイルの差分表示。削除された行が赤、追加された行が緑で並んでいる',
      en: 'A Markdown diff, with removed lines in red and added lines in green',
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

export const AICodeReviewBody: FC<{ lang: ArticleLang }> = ({ lang }) => (
  <>
    <p>
      <T
        lang={lang}
        ja="コーディングエージェントに任せる時間が増えるほど、書く時間より読む時間のほうが長くなります。この記事は、AI が書いた変更を人がどう読むかについての記録です。befold の作者が befold 自身の開発で使っている手順を、そのまま書いています。"
        en="The more you delegate to a coding agent, the more your time shifts from writing code to reading it. This is a note about how to read what the agent wrote. It describes the workflow used to build befold itself."
      />
    </p>

    <h3>
      <T lang={lang} ja="読まないと出てこない指摘がある" en="Some problems only a reader finds" />
    </h3>
    <p>
      <T
        lang={lang}
        ja="型検査も lint もテストも通っているのに、人が読むと直すべき箇所が出てきます。この記事を書いた日のセッションでは、AI が書いた 349 行の運用文書に対して 6 点の指摘が出ました。そのうち 2 つはこういうものです。"
        en="Type checks pass, the linter is quiet, the tests are green — and a human still finds things to fix. On the day this article was written, a 349-line document produced six review comments. Two of them looked like this."
      />
    </p>
    <ul>
      <li>
        <T
          lang={lang}
          ja="「この節はそもそも要らない。確定申告に関係しない情報を記録しているだけ」"
          en="“This whole section is unnecessary — it records information the task never needs.”"
        />
      </li>
      <li>
        <T
          lang={lang}
          ja="「この制約の説明は、没にした別案を比較したときの名残では」"
          en="“This constraint reads like a leftover from an option we already rejected.”"
        />
      </li>
    </ul>
    <p>
      <T
        lang={lang}
        ja="どちらも、書かれている内容が正しいかどうかの話ではありません。「そもそもここに要るのか」という問いで、機械には出せません。だから人が読む必要があり、読むための道具が要ります。"
        en="Neither is about whether the text is correct. Both ask whether it belongs there at all — a question no tool answers for you. So a person has to read it, and reading needs tooling."
      />
    </p>

    <h3>
      <T lang={lang} ja="1. 変更のあったファイルだけに絞る" en="1. Narrow to what changed" />
    </h3>
    <p>
      <T
        lang={lang}
        ja="エージェントは 1 回の作業で十数ファイルを触ります。フォルダを開くと、変更していないファイルのほうが多い状態から始まります。"
        en="An agent touches a dozen files in one go. Open the folder and most of what you see is untouched."
      />
    </p>
    <Shot lang={lang} shot={SHOTS.allFiles} />
    <p>
      <T
        lang={lang}
        ja="サイドバーを「変更のあるファイルのみ」に切り替えると、読むべきものだけが残ります。下は同じフォルダで、11 ファイルが 4 ファイルになったところです。バッジの A は追加、M は変更を表します。"
        en="Switch the sidebar to show only changed files and what is left is what you have to read. Below is the same folder, down from 11 files to 4. A marks an added file, M a modified one."
      />
    </p>
    <Shot lang={lang} shot={SHOTS.changedOnly} />

    <h3>
      <T lang={lang} ja="2. 差分のまま読む" en="2. Read it as a diff" />
    </h3>
    <p>
      <T
        lang={lang}
        ja="ファイル全体を読み直す必要はありません。差分表示に切り替えると、削除された行と追加された行が並びます。比較の起点はデフォルトブランチとの分岐点なので、コミット済みの変更も含めて「このブランチが変えたもの」全体が対象になります。"
        en="You do not need to re-read the whole file. In diff view, removed and added lines sit side by side. The comparison starts from where the branch diverged from the default branch, so committed work is included — you see everything the branch changed."
      />
    </p>
    <Shot lang={lang} shot={SHOTS.diff} />

    <h3>
      <T lang={lang} ja="3. 直させて、そのまま見続ける" en="3. Ask for a fix, keep looking" />
    </h3>
    <p>
      <T
        lang={lang}
        ja="気づいた点をエージェントに伝えて直してもらうと、開いたままのウィンドウが更新されます。開き直す必要はありません。読む → 指摘する → 直る → もう一度読む、が同じ画面で回ります。"
        en="Tell the agent what you found. When it edits the file, the open window updates on its own — no reopening. Read, comment, fix, read again, all in the same window."
      />
    </p>

    <h3>
      <T lang={lang} ja="知っておくとよいこと" en="Worth knowing" />
    </h3>
    <ul>
      <li>
        <T
          lang={lang}
          ja="差分表示は git 管理下のフォルダでだけ使えます。比較の相手が無いと成り立たないためです。"
          en="Diff view needs a git repository — without one there is nothing to compare against."
        />
      </li>
      <li>
        <T
          lang={lang}
          ja="変更が無いファイルでは差分表示を選べません。選べる状態かどうかは開いた直後には決まらず、git の状態が届いてから確定します。"
          en="A file with no changes cannot be shown as a diff. Whether it can is not settled the moment you open it; it resolves once git status arrives."
        />
      </li>
      <li>
        <T
          lang={lang}
          ja="befold は読むための道具で、編集はできません。直すのはエージェントの仕事です。"
          en="befold only reads. Fixing is the agent's job."
        />
      </li>
    </ul>
  </>
)
