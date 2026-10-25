#!/usr/bin/env python3
# CSV の描画・検索を同じ入力で比較するための、完全に架空の大きなサンプル。
# 実データの匿名化ではなく、固定語彙と乱数 seed だけから作る。入力ファイルは読まない。
#
#   python3 scripts/make-large-csv.py [出力先.csv]
#   python3 scripts/make-large-csv.py --self-test
#
# 既定の sample/large/ は gitignore 済み。生成物をコミットする必要はない。

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import random
from pathlib import Path
from urllib.parse import urlsplit

ROW_COUNT = 18_221
HEADER = ["platform", "kind", "component", "version", "repository", "archived",
          "path", "line", "scope", "evidence_url", "notes", "source_role", "use_case"]
PLATFORMS = ("desktop", "service", "worker", "browser")
KINDS = ("library", "script", "schema", "resource")
COMPONENTS = ("SampleCore", "SampleShell", "SampleTools", "SamplingKit", "Codec")
PARTS = ("core", "render", "engine", "client", "config", "module", "parser", "layout")
SCOPES = ("runtime", "test", "build", "optional")
ROLES = ("generated", "fixture-data", "example")
NOTE = ('Synthetic fixture, "sample" data for search; repeatable content for local rendering.'
        ' Generated for repeatable local rendering. Added safe neutral data.')
QUERIES = ("s", "sa", "sample", "fixture-absent-xyz")


def make_csv() -> bytes:
    rng = random.Random(0)
    output = io.StringIO(newline="")
    writer = csv.writer(output, lineterminator="\r\n")
    writer.writerow(HEADER)
    for index in range(ROW_COUNT):
        # 10/13 行だけをローカルパス候補にし、URL だけの表にしない。
        path = "unlisted"
        if index % 13 < 10:
            parts = [rng.choice(PARTS) for _ in range(rng.randint(10, 16))]
            path = "fixtures/" + "/".join(parts) + f"/item-{index:05d}.ts"
        if index == 0:
            path = "fixtures/" + ("component/" * 41)[:403] + "/item-00000.ts"
        notes = "" if index % 17 == 0 else NOTE
        if notes and index % 23 == 0:
            notes += " 架空資料"
        writer.writerow([
            rng.choice(PLATFORMS), rng.choice(KINDS), rng.choice(COMPONENTS),
            f"v{rng.randrange(1, 10)}.{rng.randrange(30)}.{rng.randrange(100)}",
            f"synthetic-{rng.randrange(100):03d}", "true" if index % 7 == 0 else "false",
            path, "" if index % 19 == 0 else str(rng.randrange(1, 10_000)),
            rng.choice(SCOPES), f"https://example.invalid/records/synthetic-item-{index:05d}",
            notes, rng.choice(ROLES), "search and scroll",
        ])
    return output.getvalue().encode("utf-8")


def summary(data: bytes) -> dict:
    text = data.decode("utf-8")
    rows = list(csv.reader(io.StringIO(text, newline="")))
    return {
        "fixture": "fully synthetic; contains no imported records",
        "bytes": len(data), "data_rows": len(rows) - 1, "columns": len(HEADER),
        "max_cell_characters": max(len(cell) for row in rows for cell in row),
        "relative_paths": sum(row[6].startswith("fixtures/") for row in rows[1:]),
        "sha256": hashlib.sha256(data).hexdigest(),
        "case_insensitive_matches": {query: text.lower().count(query.lower()) for query in QUERIES},
    }


def self_test(data: bytes) -> None:
    assert data == make_csv(), "fixed seed must reproduce identical bytes"
    text = data.decode("utf-8")
    rows = list(csv.reader(io.StringIO(text, newline="")))
    assert rows[0] == HEADER and len(rows) == ROW_COUNT + 1
    assert all(len(row) == len(HEADER) for row in rows)
    assert data.count(b"\r\n") == ROW_COUNT + 1
    assert b"\n" not in data.replace(b"\r\n", b"")
    assert 6_500_000 <= len(data) <= 7_500_000
    assert max(len(cell) for row in rows for cell in row) == 426
    assert 270_000 <= text.lower().count("s") <= 340_000
    assert "\"\"sample\"\"" in text and "架空資料" in text
    assert sum(row[6].startswith("fixtures/") for row in rows[1:]) == 14_018
    assert any(not row[7] for row in rows[1:]) and any(not row[10] for row in rows[1:])
    for row in rows[1:]:
        assert row[7] == "" or row[7].isdigit()
        assert urlsplit(row[9]).hostname == "example.invalid"
        # 数値列が増えると viewer の書式推論が変わるため、列の型を固定する。
        assert all(not cell.isdigit() for column, cell in enumerate(row) if column != 7)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate a fully synthetic large CSV fixture.")
    parser.add_argument("output", nargs="?", type=Path, default=Path("sample/large/manifest-synthetic.csv"))
    parser.add_argument("--self-test", action="store_true", help="check the fixture in memory without writing it")
    args = parser.parse_args()
    data = make_csv()
    if args.self_test:
        self_test(data)
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(data)
    print(json.dumps(summary(data), ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
