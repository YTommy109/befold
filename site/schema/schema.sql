-- events: 生 IP を保存しない集計指向テーブル（desired state）
-- visitor_day は sha256(ip + ua + YYYY-MM-DD) のハッシュのみを保持し、
-- 元の IP を復元できない形で日次ユニークを推定する。
CREATE TABLE events (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  ts          INTEGER NOT NULL,
  kind        TEXT    NOT NULL,
  version     TEXT,
  channel     TEXT,
  country     TEXT,
  os          TEXT,
  ua_summary  TEXT,
  visitor_day TEXT
);

CREATE INDEX idx_events_ts ON events (ts);

CREATE INDEX idx_events_kind ON events (kind, ts);
