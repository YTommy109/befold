#!/usr/bin/env python3
"""macOS: python3 scripts/benchmark-normalization/run.py [--base REF] [--runs N]."""
import argparse
import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import statistics
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
SOURCE = "BefoldApp/BefoldKit/NormalizedTextCache.swift"
ENCODING = "BefoldApp/BefoldKit/TextEncoding.swift"


def command(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="38afdff0")
    parser.add_argument("--runs", type=int, default=3)
    args = parser.parse_args()
    if args.runs < 3:
        parser.error("at least three alternating runs are required")
    output = ROOT / ".tmp/normalization-benchmark"
    output.mkdir(parents=True, exist_ok=True)
    spec = importlib.util.spec_from_file_location("fixture", ROOT / "scripts/make-large-csv.py")
    fixture = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fixture)
    fixture.ROW_COUNT = 100000
    (output / "manifest-100k.csv").write_bytes(fixture.make_csv())
    with (output / "narrow-1m.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream, lineterminator="\r\n")
        writer.writerow(["id", "amount", "category", "enabled", "note", "event_at"])
        for index in range(1000000):
            writer.writerow([
                index, (index * 7919) % 100000,
                ["desktop", "service", "worker", "browser"][index % 4],
                str(index % 7 == 0).lower(),
                'sample\nquoted "value"' if index % 97 == 0 else "regular note",
                "2026-10-31T08:00:00Z",
            ])
    base = command("git", "rev-parse", args.base)
    for name in ("before", "after"):
        build = output / name
        build.mkdir(exist_ok=True)
        for source in (SOURCE, ENCODING):
            contents = (command("git", "show", f"{base}:{source}") + "\n"
                        if name == "before" else (ROOT / source).read_text())
            (build / Path(source).name).write_text(contents)
        command("swiftc", "-O", str(build / "NormalizedTextCache.swift"),
                str(build / "TextEncoding.swift"),
                str(ROOT / "scripts/benchmark-normalization/main.swift"), "-o", str(build / "bench"))
    report = {
        "base": base, "swift": command("swiftc", "--version"),
        "os": command("sw_vers"), "cpu": command("sysctl", "-n", "machdep.cpu.brand_string"),
        "memory_bytes": int(command("sysctl", "-n", "hw.memsize")),
        "source_sha256": hashlib.sha256((ROOT / SOURCE).read_bytes()).hexdigest(),
        "fixtures": [],
    }
    for filename, rows in (("manifest-100k.csv", 100000), ("narrow-1m.csv", 1000000)):
        path = output / filename
        raw = path.read_bytes()
        normalized = raw.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
        expected = hashlib.sha256(normalized).hexdigest()
        entry = {"name": filename, "records": rows, "bytes": len(raw),
                 "sha256": hashlib.sha256(raw).hexdigest(), "normalized_sha256": expected,
                 "runs": {"before": [], "after": []}, "summary": {}}
        # 各測定は新規プロセス。ビルド完了後に before/after を直列で交互に実行する。
        for _ in range(args.runs):
            for name in ("before", "after"):
                entry["runs"][name].append(json.loads(command(str(output / name / "bench"), str(path))))
        for name in ("before", "after"):
            verified = json.loads(command(str(output / name / "bench"), str(path), "--verify"))
            assert verified["normalized_sha256"] == expected, (filename, name, verified)
            assert verified["normalized_bytes"] == len(normalized)
            assert verified["lines"] == normalized.count(b"\n")
            entry["summary"][name] = {
                metric: {"median": statistics.median(run[metric] for run in entry["runs"][name]),
                         "max": max(run[metric] for run in entry["runs"][name])}
                for metric in ("milliseconds", "resident_bytes", "peak_bytes")
            }
        report["fixtures"].append(entry)
    (output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
