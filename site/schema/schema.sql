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
  source      TEXT
);

CREATE INDEX idx_events_timestamp ON events (timestamp);

CREATE INDEX idx_events_kind ON events (kind, timestamp);
