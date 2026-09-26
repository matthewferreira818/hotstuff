"""Builds the price-floor sheet as a real .xlsx with live formulas.

Why a script and not a hand-made file: CLAUDE.md records rendered assets
being lost twice to a container that reverted. Everything that matters
lives in marketing/passive/planner/spec.md and in this file; the workbook
is rebuilt from them on demand.

Upload the output to Google Drive and open with Sheets — the formulas
convert. Nothing is locked or protected, deliberately: a buyer whose
processing fee differs has to be able to change it.

    python marketing/passive/make_planner_sheet.py
"""

from pathlib import Path

from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.formatting.rule import CellIsRule, FormulaRule
from openpyxl.utils import get_column_letter

OUT = Path(__file__).parent / "planner" / "price-floor-sheet.xlsx"

INK = "1D1116"
AMBER = "FFA62B"
GREEN = "1B7F4B"
RED = "B3261E"
PAPER = "FFFFFF"
SOFT = "F4F1EE"

H1 = Font(size=16, bold=True, color=INK)
H2 = Font(size=11, bold=True, color=INK)
NOTE = Font(size=9, italic=True, color="6B5B62")
BIG = Font(size=22, bold=True, color=INK)
INPUT_FILL = PatternFill("solid", fgColor="FFF6E5")
HEAD_FILL = PatternFill("solid", fgColor=SOFT)
thin = Side(style="thin", color="D8D0CC")
BOX = Border(left=thin, right=thin, top=thin, bottom=thin)

# Every fee is an INPUT, never a constant. A rate baked into a formula
# makes every copy already in a buyer's Drive wrong the day it changes.
SETTINGS = [
    ("Currency", "CAD", "Label only — this sheet does not convert currencies."),
    ("Platform fee %", 0.065, "Etsy transaction fee. Change to your platform's."),
    ("Payment processing %", 0.030, "Varies a lot by country. Check yours."),
    ("Payment processing fixed", 0.25, "Charged per order."),
    ("Listing fee", 0.20, "Per listing. Set 0 if your platform has none."),
    ("Shipping you absorb", 8.00, "Worst case, not average. The one people forget."),
    ("Minimum profit per sale", 1.00, "Your cushion. Not a fee — your floor above zero."),
    ("Offsite Ads %", 0.0, "Only on ad-attributed orders. 0 if you opted out."),
]


# Row numbers derived from SETTINGS, never typed by hand. Two formulas were
# wrong the first time because the rows were hardcoded: the floor added the
# Offsite Ads PERCENTAGE as a dollar cost and omitted the fixed processing
# fee entirely.
FIRST_ROW = 4
ROW = {name: FIRST_ROW + i for i, (name, _, _) in enumerate(SETTINGS)}
TOTAL_PCT_ROW = FIRST_ROW + len(SETTINGS) + 1

S = "'Start here'!"
PCT = f"{S}B{TOTAL_PCT_ROW}"                                  # platform+processing+ads
FIXED = f"({S}B{ROW['Payment processing fixed']}+{S}B{ROW['Listing fee']})"
SHIP = f"{S}B{ROW['Shipping you absorb']}"
MINP = f"{S}B{ROW['Minimum profit per sale']}"


def _w(ws, widths):
    for i, w in enumerate(widths, start=1):
        ws.column_dimensions[get_column_letter(i)].width = w


def start_here(wb):
    ws = wb.create_sheet("Start here")
    _w(ws, [30, 14, 62])
    ws["A1"] = "Start here — your fees"
    ws["A1"].font = H1
    ws["A2"] = ("These are starting points, not gospel. Change every one to "
                "match what your platform actually charges you.")
    ws["A2"].font = NOTE
    ws.merge_cells("A2:C2")

    r = 4
    for label, value, note in SETTINGS:
        ws.cell(r, 1, label).font = H2
        c = ws.cell(r, 2, value)
        c.fill, c.border = INPUT_FILL, BOX
        if isinstance(value, float) and value < 1:
            c.number_format = "0.00%"
        elif isinstance(value, float):
            c.number_format = "0.00"
        ws.cell(r, 3, note).font = NOTE
        r += 1

    ws.cell(r + 1, 1, "Total % fees").font = H2
    t = ws.cell(r + 1, 2, "=B5+B6+B11")
    t.number_format, t.font, t.border = "0.00%", H2, BOX
    ws.cell(r + 1, 3, "Platform + processing + offsite ads. Shown so you can "
                      "sanity-check it.").font = NOTE

    ws.cell(r + 3, 1, "What this is not").font = H2
    ws.cell(r + 4, 1, "A calculator, not accounting or tax advice. It does not "
                      "file anything or know your local rules.").font = NOTE
    ws.merge_cells(start_row=r + 4, start_column=1, end_row=r + 4, end_column=3)
    return ws


def price_floor(wb):
    ws = wb.create_sheet("Price floor")
    _w(ws, [34, 16, 58])
    ws["A1"] = "What is the lowest price I can sell this at?"
    ws["A1"].font = H1
    ws["A2"] = ("Type what the item costs you. Everything else comes from "
                "Start here.")
    ws["A2"].font = NOTE
    ws.merge_cells("A2:C2")

    ws["A4"] = "What the item costs you"
    ws["A4"].font = H2
    ws["B4"] = 6.00
    ws["B4"].fill, ws["B4"].border, ws["B4"].number_format = INPUT_FILL, BOX, "0.00"
    ws["C4"] = "Wholesale / print cost. Not including shipping."
    ws["C4"].font = NOTE

    # The percentage fee applies to the PRICE, not the cost — so you solve
    # for price rather than adding the fee on. Same shape as
    # min_profitable_price() in refresh_products.py.
    ws["A6"] = "Your price floor"
    ws["A6"].font = H2
    f = ws["B6"]
    f.value = f"=(B4+{SHIP}+{FIXED}+{MINP})/(1-{PCT})"
    f.font, f.number_format, f.border = BIG, "0.00", BOX
    f.fill = PatternFill("solid", fgColor=SOFT)
    ws["C6"] = ("Sell below this and the sale loses money once every fee is "
                "counted.")
    ws["C6"].font = NOTE

    ws["A8"] = "Your actual price"
    ws["A8"].font = H2
    ws["B8"] = 12.00
    ws["B8"].fill, ws["B8"].border, ws["B8"].number_format = INPUT_FILL, BOX, "0.00"

    ws["A9"] = "Profit per sale at that price"
    ws["A9"].font = H2
    p = ws["B9"]
    p.value = f"=B8*(1-{PCT})-{FIXED}-{SHIP}-B4"
    p.number_format, p.border = "0.00", BOX

    ws["A11"] = "Verdict"
    ws["A11"].font = H2
    v = ws["B11"]
    v.value = ('=IF(B8>=B6, "SAFE", "LOSES " & TEXT(ABS(B9),"0.00") & " A SALE")')
    v.font = Font(size=13, bold=True, color=PAPER)
    v.alignment = Alignment(horizontal="center")
    v.border = BOX
    ws.conditional_formatting.add("B11", CellIsRule(
        operator="equal", formula=['"SAFE"'],
        fill=PatternFill("solid", fgColor=GREEN), font=Font(bold=True, color=PAPER)))
    ws.conditional_formatting.add("B11", CellIsRule(
        operator="notEqual", formula=['"SAFE"'],
        fill=PatternFill("solid", fgColor=RED), font=Font(bold=True, color=PAPER)))
    ws["C11"] = ("Red is the whole point of this sheet. A 2x markup goes red "
                 "more often than anyone expects.")
    ws["C11"].font = NOTE
    return ws


def products(wb):
    ws = wb.create_sheet("Your products")
    heads = ["SKU", "Name", "Cost", "Shipping (blank = default)",
             "Your price", "Floor", "Profit/sale", "Verdict"]
    _w(ws, [14, 30, 10, 22, 12, 10, 12, 22])
    ws["A1"] = "Every product, checked against its own floor"
    ws["A1"].font = H1
    for i, h in enumerate(heads, start=1):
        c = ws.cell(3, i, h)
        c.font, c.fill, c.border = H2, HEAD_FILL, BOX

    for r in range(4, 34):
        ship = f'IF(D{r}="",{SHIP},D{r})'
        ws.cell(r, 6, f'=IF(C{r}="","",(C{r}+{ship}+{FIXED}+{MINP})'
                      f'/(1-{PCT}))').number_format = "0.00"
        ws.cell(r, 7, f'=IF(OR(C{r}="",E{r}=""),"",'
                      f'E{r}*(1-{PCT})-{FIXED}-{ship}-C{r})').number_format = "0.00"
        ws.cell(r, 8, f'=IF(OR(C{r}="",E{r}=""),"",IF(E{r}>=F{r},"SAFE",'
                      f'"LOSES "&TEXT(ABS(G{r}),"0.00")))')
    rng = "H4:H33"
    ws.conditional_formatting.add(rng, CellIsRule(
        operator="equal", formula=['"SAFE"'],
        fill=PatternFill("solid", fgColor="DFF3E6")))
    # "not SAFE and not blank" == a losing row. Expressed as a formula rule
    # because CellIsRule has no beginsWith text operator.
    ws.conditional_formatting.add(rng, FormulaRule(
        formula=['AND(H4<>"",H4<>"SAFE")'],
        fill=PatternFill("solid", fgColor="FBE3E1")))
    ws.cell(35, 1, "Add rows as you need them — the formulas copy down.").font = NOTE
    return ws


def ads(wb):
    ws = wb.create_sheet("Ads")
    _w(ws, [34, 16, 58])
    ws["A1"] = "What do ads have to return before they pay for themselves?"
    ws["A1"].font = H1
    ws["A3"] = "Your price"
    ws["A3"].font = H2
    ws["B3"] = "='Price floor'!B8"
    ws["B3"].number_format = "0.00"
    ws["A4"] = "Profit per sale"
    ws["A4"].font = H2
    ws["B4"] = "='Price floor'!B9"
    ws["B4"].number_format = "0.00"
    ws["A6"] = "Break-even ROAS"
    ws["A6"].font = H2
    b = ws["B6"]
    b.value = '=IF(B4<=0,"n/a — you lose money before ads",B3/B4)'
    b.font, b.number_format, b.border = BIG, "0.00", BOX
    ws["C6"] = ("Every $1 of ads must bring back this much in sales just to "
                "break even. Below it you are donating.")
    ws["C6"].font = NOTE
    return ws


def month(wb):
    ws = wb.create_sheet("This month")
    _w(ws, [34, 16, 58])
    ws["A1"] = "Did I make money this month?"
    ws["A1"].font = H1
    rows = [("Revenue", 0.0), ("Platform + processing fees", 0.0),
            ("Cost of goods", 0.0), ("Shipping you paid", 0.0),
            ("Refunds and chargebacks", 0.0), ("Ad spend", 0.0)]
    r = 3
    for label, v in rows:
        ws.cell(r, 1, label).font = H2
        c = ws.cell(r, 2, v)
        c.fill, c.border, c.number_format = INPUT_FILL, BOX, "0.00"
        r += 1
    ws.cell(3, 3, "Processors usually keep the fixed fee on a refunded "
                  "order. Count it.").font = NOTE
    ws.cell(r + 1, 1, "Actually made").font = H2
    tot = ws.cell(r + 1, 2, f"=B3-B4-B5-B6-B7-B8")
    tot.font, tot.number_format, tot.border = BIG, "0.00", BOX
    ws.cell(r + 3, 1, "Set aside for tax").font = H2
    ws.cell(r + 3, 2, 0.25).number_format = "0%"
    ws.cell(r + 3, 2).fill = INPUT_FILL
    ws.cell(r + 4, 1, "Put this much away").font = H2
    a = ws.cell(r + 4, 2, f"=MAX(0,B{r+1})*B{r+3}")
    a.number_format, a.border = "0.00", BOX
    ws.cell(r + 4, 3, "A bucket, not tax advice. Your rate is yours.").font = NOTE
    return ws


def build():
    wb = Workbook()
    wb.remove(wb.active)
    start_here(wb)
    price_floor(wb)
    products(wb)
    ads(wb)
    month(wb)
    wb.active = 1          # opens on the floor tab, which is the product
    OUT.parent.mkdir(parents=True, exist_ok=True)
    wb.save(OUT)
    print(f"wrote {OUT.relative_to(Path(__file__).parents[2])}  "
          f"({OUT.stat().st_size:,} bytes, {len(wb.sheetnames)} tabs)")


if __name__ == "__main__":
    build()
