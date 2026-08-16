-- events: 生 IP を保存しない集計指向テーブル（desired state）
-- visitor_token は sha256(ip + ua + YYYY-MM-DD) のハッシュのみを保持し、
-- 元の IP を復元できない形で日次ユニークを推定する。日付を材料に混ぜるため
-- 翌日には別の値になり、日をまたぐ同一人物の追跡はできない（意図した性質）。
CREATE TABLE events (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp   INTEGER NOT NULL,
  kind        TEXT    NOT NULL,
  version     TEXT,
  channel     TEXT,
  country     TEXT,
  os          TEXT,
  ua_summary  TEXT,
  visitor_token TEXT,
  referrer    TEXT,
  as_org      TEXT,
  -- ダウンロードの発生経路。'lp' は配布 LP の /download 経由、'sparkle' は
  -- appcast の enclosure（自動アップデート）経由。両者は性質がまったく違う
  -- （前者は新規獲得、後者は既存ユーザの更新）ため、kind='download' のまま
  -- 混ぜると LP のダウンロード数が意味を失う。download 以外の kind では NULL。
  source      TEXT,
  -- 訪問されたページ。kind='visit' のときだけ値を持ち、それ以外の kind では NULL。
  -- 列の導入前に記録された visit 行も NULL で、当時 visit を計上していたのは LP
  -- だけ（src/routes/public.tsx）なので '/' と読んでよい。この二重の意味がある
  -- ため、`COALESCE(page, '/')` は kind='visit' と同じ条件節の中でしか使えない
  -- （download / update_check にはページの概念が無く、'/' を与えると嘘になる）。
  page        TEXT,
  -- Accept-Language の第一言語タグを 'ja' / 'en' / 'other' に丸めたもの。
  -- これは**ブラウザの言語設定**であって、実際に読まれた言語ではない。LP は
  -- 日英を同一 HTML に持ち、localStorage の befold-lang が未設定なら常に日本語を
  -- 表示する（src/views/shared.tsx）ため、en 設定の初回訪問者も日本語を読んでいる。
  -- Accept-Language を送らないクライアント（Sparkle など）では NULL。
  browser_lang TEXT,
  -- 実際に配信したページの言語。kind='visit' のときだけ値を持つ。
  -- browser_lang と対で読む（前者は求めた言語、こちらは実際に出した言語）。
  -- page 列と同じく NULL には 2 つの意味がある: 列の導入前に記録された visit
  -- （当時は日英を同一 HTML で出しており表示言語が確定しない）と、ページの概念が
  -- 無い download / update_check。このため `COALESCE(display_lang, 'ja')` は
  -- 無条件には書けない（kind='visit' と同じ条件節の中でのみ使う）。
  display_lang TEXT
);

CREATE INDEX idx_events_timestamp ON events (timestamp);

CREATE INDEX idx_events_kind ON events (kind, timestamp);
