-- OS 列から macOS のバージョンを落とす（TASK-904）。ブラウザは UA の macOS バージョンを
-- 10_15_7 に固定するため、記録済みの「macOS 10.15」などは実際の版を表さない。
-- 新規の記録は summarizeOS がバージョンを付けなくなったので、既存の行だけを揃える。
UPDATE `events` SET `os` = 'macOS' WHERE `os` LIKE 'macOS %';
