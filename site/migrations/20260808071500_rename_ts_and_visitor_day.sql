-- Rename column "ts" to "timestamp" on table: "events"
-- 列名が省略形で日時列と分からなかったため。RENAME COLUMN なのでデータは保持される。
ALTER TABLE `events` RENAME COLUMN `ts` TO `timestamp`;
-- Rename column "visitor_day" to "visitor_token" on table: "events"
-- 実体は日付ではなく sha256(ip + ua + 日付) の 64 桁ハッシュ（その日限りの訪問者トークン）。
ALTER TABLE `events` RENAME COLUMN `visitor_day` TO `visitor_token`;
-- Rename index "idx_events_ts" to "idx_events_timestamp"
-- SQLite は RENAME COLUMN でインデックス定義の参照を自動追従するが、
-- インデックス名は古いままになるため貼り直す（データではなく索引の再構築）。
DROP INDEX `idx_events_ts`;
CREATE INDEX `idx_events_timestamp` ON `events` (`timestamp`);
