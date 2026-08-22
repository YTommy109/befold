#!/usr/bin/env python3
# scripts/make-medical-sample.py
#
# 医療費控除のユースケース記事（TASK-538）用に、使い捨てのサンプル一式を作る。
#
# site/public/templates/medical-expenses/README.md に書いた運用が実際に通るかを
# 確かめるためのもので、次の 2 つを兼ねる。
#
# 1. README の手順（pdfimages → Pillow の autocontrast → pypdf で分割 →
#    集計表へ追記 → receipts/ へリネーム移動）を最後まで実行する
# 2. 記事に載せるスクリーンショットの被写体を作る
#
# 出てくる氏名・医療機関・住所・電話番号・金額はすべて架空。実在のものは使わない。
#
# 依存は Pillow と pypdf のみ（poppler-utils は読み取りの確認に使うだけで、
# このスクリプト自体は要求しない）。
#
#     python3 -m venv venv && ./venv/bin/pip install pillow pypdf
#     ./venv/bin/python scripts/make-medical-sample.py /path/to/out
#
# 出力先を消して作り直すので、リポジトリ内を指さないこと。

from __future__ import annotations

import random
import shutil
import sys
from pathlib import Path

import pypdf
from PIL import Image, ImageDraw, ImageFont

FONT = "/System/Library/Fonts/Hiragino Sans GB.ttc"

# 架空の 4 人家族。**姓は全員同じ・名は全員異なる**——テンプレートの氏名規約
# （領収書のファイル名だけ名のみ）が成立する条件そのものなので、崩さないこと。
FAMILY = ["北原 健吾", "北原 沙織", "北原 悠真", "北原 芽衣"]

# スキャン 1 ファイルぶん。pages が 2 つあるものは「領収証 + 明細書」を
# 1 ファイルにまとめて撮った場合を表す（pypdf の分割を通すため必ず 1 件入れる）。
SCANS = [
    {
        "file": "スキャン 2026-01-10 09.12.pdf",
        "date": "2026-01-10",
        "person": "北原 芽衣",
        "provider": "みなみ野内科クリニック",
        "category": "診療",
        "amount": 1080,
        "pages": [
            {"title": "領 収 証", "lines": [("受診日", "2026年1月10日"),
                                            ("領収金額", "¥1,080"),
                                            ("内訳", "初診料・投薬"),
                                            ("負担割合", "3割")]},
        ],
    },
    {
        "file": "スキャン 2026-02-03 20.41.pdf",
        "date": "2026-02-03",
        "person": "北原 沙織",
        "provider": "かえで調剤薬局",
        "category": "医薬品",
        "amount": 3200,
        "pages": [
            {"title": "領 収 証", "lines": [("調剤日", "2026年2月3日"),
                                            ("領収金額", "¥3,200"),
                                            ("内訳", "調剤技術料・薬剤料")]},
            {"title": "調 剤 明 細 書", "lines": [("調剤日", "2026年2月3日"),
                                                  ("薬剤名", "（架空の薬剤）錠 14日分"),
                                                  ("合計点数", "320点")]},
        ],
    },
    {
        "file": "スキャン 2026-02-18 18.05.pdf",
        "date": "2026-02-18",
        "person": "北原 悠真",
        "provider": "ひなた歯科医院",
        "category": "診療",
        "amount": 4530,
        "pages": [
            {"title": "領 収 証", "lines": [("受診日", "2026年2月18日"),
                                            ("領収金額", "¥4,530"),
                                            ("内訳", "処置・歯科診療")]},
        ],
    },
    {
        "file": "スキャン 2026-03-05 11.27.pdf",
        "date": "2026-03-05",
        "person": "北原 健吾",
        "provider": "みなみ野内科クリニック",
        "category": "診療",
        "amount": 2150,
        "pages": [
            {"title": "領 収 証", "lines": [("受診日", "2026年3月5日"),
                                            ("領収金額", "¥2,150"),
                                            ("内訳", "再診料・検査")]},
        ],
    },
]

MEDICAL_HEADER = ["date", "person", "provider", "category",
                  "amount", "reimbursed", "receipt", "note"]
INCOME_HEADER = ["year", "person", "kind", "revenue", "income", "withheld", "note"]


def render_page(scan: dict, page: dict, seed: int) -> Image.Image:
    """紙をスキャンしたような画像を 1 枚作る。

    真っ白・真っ黒にしないのが要点。実際のスキャンは紙の地色がくすみ、
    インクも沈むため、コントラストを詰めておくと autocontrast の効きを
    確かめられない（README の手順が「効いている」ことを見せられない）。
    """
    rng = random.Random(seed)
    w, h = 1240, 1754  # A4 相当・150dpi
    paper = rng.randint(214, 228)
    ink = rng.randint(70, 92)

    im = Image.new("L", (w, h), paper)
    d = ImageDraw.Draw(im)
    title_font = ImageFont.truetype(FONT, 64)
    body_font = ImageFont.truetype(FONT, 40)
    small_font = ImageFont.truetype(FONT, 32)

    d.text((w // 2, 220), page["title"], font=title_font, fill=ink, anchor="mm")
    d.line((160, 300, w - 160, 300), fill=ink, width=3)
    d.text((160, 380), scan["provider"], font=body_font, fill=ink)
    d.text((160, 440), "〒000-0000 〇〇県〇〇市〇〇 1-2-3", font=small_font, fill=ink)
    d.text((160, 490), "TEL 0XX-XXX-XXXX", font=small_font, fill=ink)

    y = 620
    for label, value in [("患者氏名", f"{scan['person']} 様"), *page["lines"]]:
        d.text((200, y), label, font=body_font, fill=ink)
        d.text((640, y), value, font=body_font, fill=ink)
        y += 90

    d.line((160, y + 40, w - 160, y + 40), fill=ink, width=2)
    d.text((160, y + 90), "上記正に領収いたしました", font=small_font, fill=ink)
    d.text((160, y + 150), "※ この書類はサンプル用に生成した架空のものです",
           font=small_font, fill=ink)

    # スキャン特有のわずかな傾き
    return im.rotate(rng.uniform(-0.8, 0.8), resample=Image.BICUBIC, fillcolor=paper)


def write_tsv(path: Path, header: list[str], rows: list[list[str]]) -> None:
    """タブ区切りで書く。表計算ソフトを通さないので書式は崩れない。"""
    body = "\n".join("\t".join(r) for r in [header, *rows])
    path.write_text(body + "\n", encoding="utf-8")


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(f"usage: {sys.argv[0]} <出力先ディレクトリ>")
    root = Path(sys.argv[1])
    if root.exists():
        shutil.rmtree(root)
    inbox = root / "Inbox"
    inbox.mkdir(parents=True)

    # 1. スキャンを Inbox に投入する（テキスト層を持たない画像 PDF）
    for i, scan in enumerate(SCANS):
        pages = [render_page(scan, p, seed=i * 10 + j)
                 for j, p in enumerate(scan["pages"])]
        pages[0].save(inbox / scan["file"], "PDF", resolution=150.0,
                      save_all=True, append_images=pages[1:])

    # 2〜4. 取り込む: 必要なページを取り出して receipts/ へ、元は trash/ へ、
    #       集計表へ追記する。順序は README の「2. 取り込む」に合わせてある。
    rows: dict[str, list[list[str]]] = {}
    for scan in SCANS:
        year = scan["date"][:4]
        folder = scan["person"].replace(" ", "")
        given = scan["person"].split(" ")[1]
        out_dir = root / "receipts" / year / folder
        out_dir.mkdir(parents=True, exist_ok=True)
        name = f"{scan['date']}_{scan['provider']}_{given}_{scan['amount']}.pdf"

        reader = pypdf.PdfReader(inbox / scan["file"])
        writer = pypdf.PdfWriter()
        for page in reader.pages:
            writer.add_page(page)
        with open(out_dir / name, "wb") as f:
            writer.write(f)

        (root / "trash").mkdir(exist_ok=True)
        shutil.move(inbox / scan["file"], root / "trash" / scan["file"])

        rows.setdefault(folder, []).append(
            [scan["date"], scan["person"], scan["provider"], scan["category"],
             str(scan["amount"]), "0", name, ""])

    # 通院交通費（領収書が無い行）も 1 件入れる。receipt 列が空の見た目を
    # スクリーンショットに残しておきたいため。
    rows["北原芽衣"].append(
        ["2026-01-10", "北原 芽衣", "公共交通機関", "その他", "440", "0", "",
         "自宅→みなみ野内科クリニック 往復"])

    data = root / "data"
    data.mkdir()
    for folder, rs in rows.items():
        rs.sort()
        write_tsv(data / f"medical-2026-{folder}.tsv", MEDICAL_HEADER, rs)

    # 所得。金額は架空だが、足切り（10 万円 と 総所得の 5% の低い方）の比較が
    # 意味を持つよう、片方を 200 万円未満にしてある。
    write_tsv(data / "income.tsv", INCOME_HEADER, [
        ["2026", "北原 健吾", "給与", "6200000", "4480000", "132400", ""],
        ["2026", "北原 沙織", "給与", "1560000", "1010000", "0", ""],
    ])

    for d in ("Inbox", "docs/2026/北原悠真"):
        (root / d).mkdir(parents=True, exist_ok=True)

    template = Path(__file__).resolve().parents[1] / \
        "site/public/templates/medical-expenses"
    for name in ("README.md", "CLAUDE.md"):
        shutil.copy(template / name, root / name)

    print(f"作成: {root}")
    print(f"  data/      集計表 {len(rows)} 人分 + income.tsv")
    print(f"  receipts/  領収書 {len(SCANS)} 件")
    print(f"  trash/     取り込み済みの元スキャン {len(SCANS)} 件")
    print(f"  家族: {' / '.join(FAMILY)}（すべて架空）")


if __name__ == "__main__":
    main()
