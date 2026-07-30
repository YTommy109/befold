-- Create "events" table
CREATE TABLE `events` (
  `id` integer NULL PRIMARY KEY AUTOINCREMENT,
  `ts` integer NOT NULL,
  `kind` text NOT NULL,
  `version` text NULL,
  `channel` text NULL,
  `country` text NULL,
  `os` text NULL,
  `ua_summary` text NULL,
  `visitor_day` text NULL
);
-- Create index "idx_events_ts" to table: "events"
CREATE INDEX `idx_events_ts` ON `events` (`ts`);
-- Create index "idx_events_kind" to table: "events"
CREATE INDEX `idx_events_kind` ON `events` (`kind`, `ts`);
