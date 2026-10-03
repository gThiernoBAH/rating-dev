import csv, sys
from pathlib import Path
from openpyxl import Workbook

src = Path(sys.argv[1])
for f in sorted(src.glob("*.csv")):
    wb = Workbook(); ws = wb.active
    with open(f, newline="", encoding="utf-8-sig") as fh:
        for row in csv.reader(fh, delimiter="|"):
            if row:
                ws.append([None if v == "NULL" or v == "" else v for v in row])
    wb.save(src / (f.stem + ".xlsx"))
    print(f.stem + ".xlsx")