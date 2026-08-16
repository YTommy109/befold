-- Add column "host" to table: "events"
ALTER TABLE `events` ADD COLUMN `host` text NULL;
-- Add column "fallback" to table: "events"
ALTER TABLE `events` ADD COLUMN `fallback` text NULL;
