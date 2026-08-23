How do you add up a whole family’s medical bills for a tax deduction? Until now I typed them into a spreadsheet by hand. Not any more.

Scan the receipt with your phone and drop it in a folder — that is the whole job. Then you ask Claude to take them in, and it files them and builds the ledger for you. The [CLAUDE.md](/templates/medical-expenses/CLAUDE.md) and [README.md](/templates/medical-expenses/README.md) I actually run are right here.

### The family side is simple too

Create a “医療費” folder with an “Inbox” inside it on iCloud Drive and **share the Inbox with your family**. That is the whole setup.

> When you get a receipt from a clinic or pharmacy, open the “Inbox” folder in the iPhone Files app and choose “Scan Documents” from the … menu. Take the photo and save. The filename can be anything.

<figure class="article-shots portrait"><img src="/images/usecase-medical-scan-en.png" alt="A folder open in the iPhone Files app with the top-right menu showing, including “Scan Documents”" loading="lazy" width="571" height="1242"/></figure>

### Then you ask Claude for this

> If there are new files, take them in!

That is all it takes.

1. Read the date, provider, amount, patient and category out of each unprocessed file in the inbox
2. Append it to the per-year, per-person TSV ledger, in date order
3. Rename the scan to “date_provider_patient_amount.pdf” and move it into the year and person folder under receipts/
4. Report anything it could not read, or whose patient is ambiguous — never fill it in by guessing

The steps and the TSV spec live in a README.md and CLAUDE.md inside the folder, so none of it has to be re-explained each time.

### Checking is easiest in befold

Every file in the 医療費 folder can be checked in befold. The TSV ledger, the receipt PDFs, the Markdown that describes the workflow — all of them open in the same window.

#### 1. Read the TSV without a spreadsheet

The ledger is tab-separated text, and befold lays it out as a table. Open it in a spreadsheet and save it back and a leading zero can vanish or a date format can change. The next reader is an LLM, so it breaks silently. Read it in a viewer, ask for edits.

<figure class="article-shots"><img src="/images/usecase-medical-tsv.png" alt="The TSV ledger rendered as a table in befold, with date, person, provider, amount and receipt columns" loading="lazy" width="1512" height="949"/></figure>

#### 2. Jump from a row to its receipt

The receipt column carries the filename. Open that PDF from the sidebar and compare the amount and date against the original. When a file is corrected the window updates in place — no reopening.

<figure class="article-shots"><img src="/images/usecase-medical-receipt.png" alt="A scanned receipt PDF previewed in befold" loading="lazy" width="1512" height="949"/></figure>

#### 3. Read the rules written for the LLM

The README.md and CLAUDE.md are written for the LLM, but the one who forgets how it works is you. Six months later, when you need to recall how travel costs are recorded, reading it as rendered Markdown is quicker.

<figure class="article-shots"><img src="/images/usecase-medical-readme.png" alt="The README describing the workflow shown in befold, with the folder tree in the sidebar" loading="lazy" width="1512" height="949"/></figure>

### The template

Copy it and use it. Every name, clinic, address and phone number is a placeholder, and the screenshots in this article use the same fictional data.

- [README.md](/templates/medical-expenses/README.md) — Folder layout, the workflow, and the TSV spec
- [CLAUDE.md](/templates/medical-expenses/CLAUDE.md) — The entry point for the LLM: read the README, never guess a value

### Worth knowing

- Don’t throw the paper away. Receipts no longer have to be submitted for this deduction, but you must keep them at home for five years.
- The category column matches the four buckets on the deduction form, so the year-end numbers transcribe directly.
- befold only reads. Fixing is the LLM’s job.

<p class="listing-note">This article is not tax advice. Which costs qualify, and how long you must keep the paperwork, can change. Check the National Tax Agency’s guidance and ask your tax office when in doubt.</p>

<ul class="listing-note"><li><a href="https://www.nta.go.jp/taxes/shiraberu/taxanswer/shotoku/1119_qa.htm">No.1119 Procedures for the medical expense deduction (National Tax Agency, in Japanese)</a></li><li><a href="https://www.nta.go.jp/taxes/shiraberu/shinkoku/tebiki/2025/06/6_01.htm">The medical expense deduction statement (National Tax Agency, in Japanese)</a></li></ul>

### Try befold

{{cta}}
