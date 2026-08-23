How do you add up a whole family’s medical bills for a tax deduction? Until now I typed them into a spreadsheet by hand. Not any more.

Scan the receipt with your phone and drop it in a folder — that is the whole job. Then you ask Claude to take them in, and it files them and builds the ledger for you. The [CLAUDE.md](/templates/medical-expenses/CLAUDE.md) and [README.md](/templates/medical-expenses/README.md) I actually run are right here.

### What the family has to do fits in three lines

First, create a “医療費” folder with an “Inbox” inside it on iCloud Drive and **share the Inbox with your family**. That is the whole setup; from there you ask the family for this.

> When you get a receipt from a clinic or pharmacy, open the “Inbox” folder in the iPhone Files app and choose “Scan Documents” from the … menu. Take the photo and save. The filename can be anything.

<figure class="article-shots portrait"><img src="/images/usecase-medical-scan-en.png" alt="A folder open in the iPhone Files app with the top-right menu showing, including “Scan Documents”" loading="lazy" width="571" height="1242"/></figure>

No input form was built. For anything you have to ask your family to keep doing, the biggest risk is that extra steps make it stop. One photo keeps going. Naming and filing are pushed downstream.

### Batch it and you can’t read it; do it daily and you stop

A medical expense deduction covers a whole year of receipts, but you only add them up once. Let them pile up in an envelope and you face an unreadable stack in December. Type each one into a household ledger as it arrives and you quit by March.

So the work is split three ways: drop it in as it arrives, collate once a month, and check with human eyes. Each part stays small enough to keep doing.

### Once a month, you ask for this

> Read the new scans in the inbox, append them to the ledger, then rename and move them into receipts/.

That one line does this:

1. Read the date, provider, amount, patient and category out of each unprocessed file in the inbox
2. Append it to the per-year, per-person TSV ledger, in date order
3. Rename the scan to “date_provider_patient_amount.pdf” and move it into the year and person folder under receipts/
4. Report anything it could not read, or whose patient is ambiguous, and ask — never fill it in by guessing

How to read the scans and what the TSV columns mean live in a README.md and CLAUDE.md inside the folder itself, so none of it has to be re-explained each month. The template is linked at the end of this article.

### Only a person notices a misreading

It tells you what it could not read. It cannot tell you what it read wrong — a digit in the amount, a similar date, the wrong family member. That part needs a person, and befold keeps the whole check inside one window.

#### 1. Read the TSV without a spreadsheet

The ledger is tab-separated text, and befold lays it out as a table. Open it in a spreadsheet and save it back and a leading zero can vanish or a date format can change — and the next reader of that file is an LLM, so it breaks silently. Read it in a viewer, ask for edits, and the format stays intact.

<figure class="article-shots"><img src="/images/usecase-medical-tsv.png" alt="The TSV ledger rendered as a table in befold, with date, person, provider, amount and receipt columns" loading="lazy" width="1512" height="949"/></figure>

#### 2. Jump from a row to its receipt

Each row carries the receipt’s filename. Open that PDF from the sidebar and compare the amount and date against the original. When a file is corrected the window updates in place — no reopening.

<figure class="article-shots"><img src="/images/usecase-medical-receipt.png" alt="A scanned receipt PDF previewed in befold" loading="lazy" width="1512" height="949"/></figure>

#### 3. Read the rules written for the LLM

The README.md and CLAUDE.md are written for the LLM, but the one who forgets how the system works is you. Six months later, when you need to recall how travel costs are recorded, reading it as rendered Markdown is quicker.

<figure class="article-shots"><img src="/images/usecase-medical-readme.png" alt="The README describing the workflow shown in befold, with the folder tree in the sidebar" loading="lazy" width="1512" height="949"/></figure>

### Take it with you: the template

A copy-and-use template. Every name, clinic, address and phone number in it is a placeholder, and the screenshots in this article use the same fictional data.

- [README.md](/templates/medical-expenses/README.md) — Folder layout, the monthly workflow, and the TSV spec — the single source of truth
- [CLAUDE.md](/templates/medical-expenses/CLAUDE.md) — The entry point for the LLM: read the README, and never fill in a value by guessing

### Worth knowing

- Scanning does not let you throw the paper away. Receipts no longer have to be submitted for this deduction, but you must keep them at home for five years. The scan is for searching and adding up; the paper is for the retention rule. You keep both.
- The category column matches the four buckets on the deduction form, so the year-end numbers transcribe directly.
- befold only reads. Fixing is the LLM’s job.

<p class="listing-note">This article is not tax advice. Which costs qualify, and how long you must keep the paperwork, can change. Check the National Tax Agency’s guidance and ask your tax office when in doubt.</p>

<ul class="listing-note"><li><a href="https://www.nta.go.jp/taxes/shiraberu/taxanswer/shotoku/1119_qa.htm">No.1119 Procedures for the medical expense deduction (National Tax Agency, in Japanese)</a></li><li><a href="https://www.nta.go.jp/taxes/shiraberu/shinkoku/tebiki/2025/06/6_01.htm">The medical expense deduction statement (National Tax Agency, in Japanese)</a></li></ul>

### Try befold

{{cta}}
