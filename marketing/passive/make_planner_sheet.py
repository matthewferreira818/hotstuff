"""Builds the price-floor sheet as a real .xlsx with live formulas.

Why a script and not a hand-made file: CLAUDE.md records rendered assets
being lost twice to a container that reverted. Everything that matters
lives in marketing/passive/planner/spec.md and in this file; the workbook
is rebuilt from them on demand.

Upload the output to Google Drive and open with Sheets — the formulas
convert. Nothing is locked or protected, deliberately: a buyer whose
processing fee differs has to be able to change it.

Design v2, "Grid & Signal" (2026-09-27). v1 read as vintage: cream and
amber, Calibri, italics, gridlines, a thin box around every input. All of
that is deleted rather than redrawn. What's left is white paper, one
typeface, space measured in ten fixed row heights, and one colour — signal
red — which appears only where the sheet says you are losing money.
Rationale and the panel's scoring are in planner/spec.md.

    python marketing/passive/make_planner_sheet.py
"""

import re
from pathlib import Path

from openpyxl import Workbook
from openpyxl.formatting.rule import FormulaRule
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter

OUT = Path(__file__).parent / "planner" / "price-floor-sheet.xlsx"

# ── Tokens ────────────────────────────────────────────────────────────────
# Four neutrals and one colour. FF alpha on every value: a colour written
# with alpha 00 is read as transparent by some converters.
PAPER = "FFFFFFFF"      # canvas and every input cell
INK = "FF111111"        # all type, all structural rules
MUTED = "FF6E6E6E"      # notes, eyebrows — on white only (5.1:1)
COMPUTED = "FFEDEDED"   # "the sheet worked this out"
HAIR = "FFBFBFBF"       # hairline row rules, never type
SIGNAL = "FFE30613"     # losing money. Nowhere else.


def solid(argb):
    # start AND end colour. PatternFill("solid", fgColor=X) inside a
    # conditional format writes fgColor alone with alpha 00, which is how
    # v1's CF fills were written.
    return PatternFill(start_color=argb, end_color=argb, fill_type="solid")


def arial(size=10, bold=False, color=INK):
    # Every cell names Arial, including the blank canvas, so a buyer's
    # typing never appears in the workbook default (Calibri).
    return Font(name="Arial", size=size, bold=bold, color=color)


FILL_PAPER, FILL_COMPUTED, FILL_SIGNAL = solid(PAPER), solid(COMPUTED), solid(SIGNAL)
RULE_INK = Side(style="medium", color=INK)      # bottom only (one top: the total)
RULE_HAIR = Side(style="thin", color=HAIR)      # bottom only

MONEY = "#,##0.00;-#,##0.00"   # no $: the symbol is an input on Start here
RATE = "0.00%"                 # two places, because 1.75% exists
ROAS = '0.0"x"'

LEFT = Alignment(horizontal="left", vertical="center")
LEFT_LOW = Alignment(horizontal="left", vertical="bottom")
RIGHT = Alignment(horizontal="right", vertical="center")
RIGHT_LOW = Alignment(horizontal="right", vertical="bottom")
CENTER = Alignment(horizontal="center", vertical="center")
WRAP = Alignment(horizontal="left", vertical="center", wrap_text=True)

# The only row heights allowed anywhere, in points. _audit() enforces it.
HEIGHTS = {8, 14, 16, 20, 22, 28, 32, 36, 52, 104}

# A margin · B labels · C gutter · D values · E gutter · F notes · G margin.
# B+C+D = 382px, which is the width of the verdict block.
PANEL_WIDTHS = [3.0, 30.0, 2.5, 20.0, 2.5, 42.0, 3.0]
PRODUCT_WIDTHS = [3.0, 12, 28, 11, 16, 12, 11, 12, 20, 3.0]

LEGEND = ("White cells are yours to type in. Grey cells are worked out. "
          "Nothing is locked.")
DISCLAIMER = "A calculator, not accounting or tax advice."

# ── Start here: the fee inputs ────────────────────────────────────────────
# Every fee is an INPUT, never a constant. A rate baked into a formula
# makes every copy already in a buyer's Drive wrong the day it changes.
# The three percentages sit together so their total can't skip one.
SETTINGS = [
    ("pct_platform", "Platform fee %", 0.065, RATE, "01",
     "Etsy transaction fee. Change to your platform's."),
    ("pct_processing", "Payment processing %", 0.030, RATE, "01",
     "Varies a lot by country. Check yours."),
    ("pct_offsite", "Offsite Ads %", 0.0, RATE, "01",
     "Only on ad-attributed orders. 0 if you opted out."),
    ("fix_processing", "Payment processing fixed", 0.25, MONEY, "02",
     "Charged per order."),
    ("fix_listing", "Listing fee", 0.20, MONEY, "02",
     "Per listing. Set 0 if your platform has none."),
    ("ship", "Shipping you absorb", 8.00, MONEY, "02",
     "Worst case, not average. The one people forget."),
    ("minp", "Minimum profit per sale", 1.00, MONEY, "03",
     "Your cushion. Not a fee — your floor above zero."),
    ("cur", "Currency symbol", "$", "@", "04",
     "Cosmetic. This sheet does not convert currencies."),
]
GROUPS = [("01", "PERCENTAGE FEES"), ("02", "PER-ORDER COSTS"),
          ("03", "YOUR CUSHION"), ("04", "CURRENCY SYMBOL")]


def _start_here_plan():
    """Start here, row by row from row 1: (height, kind, payload)."""
    plan = [(8, "spacer", None), (14, "masthead", None),
            (28, "headline", "Start here — your fees"),
            (16, "legend", LEGEND), (8, "spacer", None)]
    for code, title in GROUPS:
        plan.append((14, "eyebrow", f"{code}  {title}"))
        plan += [(22, "setting", s) for s in SETTINGS if s[4] == code]
        plan.append((8, "spacer", None))
    plan += [(14, "eyebrow", "05  CALCULATED FOR YOU"), (28, "total", None),
             (8, "spacer", None), (14, "eyebrow", "06  WHAT THIS IS NOT"),
             (20, "disclaimer", "A calculator, not accounting or tax advice. "
                                "It does not file anything or know your local rules.")]
    return plan


# Row numbers derived from the plan, never typed by hand. Two v1 formulas
# were wrong because rows were hardcoded: the floor added the Offsite Ads
# PERCENTAGE as a dollar cost and left out the fixed processing fee, and
# the total survived as a literal "=B5+B6+B11".
PLAN = _start_here_plan()
ROW = {p[2][0]: r for r, p in enumerate(PLAN, start=1) if p[1] == "setting"}
ROW_TOTAL = next(r for r, p in enumerate(PLAN, start=1) if p[1] == "total")

# ── Every cross-sheet reference, built in one place ───────────────────────
S = "'Start here'!"
PCT = f"{S}$D${ROW_TOTAL}"                                   # all % fees
FIXED = f"({S}$D${ROW['fix_processing']}+{S}$D${ROW['fix_listing']})"
SHIP = f"{S}$D${ROW['ship']}"
MINP = f"{S}$D${ROW['minp']}"
CUR = f"{S}$D${ROW['cur']}"

# Price floor anchors. Merged ranges are referenced by their ANCHOR (top
# left) cell — the other cells of a merge are always blank.
PF_COST, PF_PRICE, PF_FLOOR, PF_PROFIT = "$D$7", "$D$8", "$B$11", "$B$13"
PF_PRICE_X = f"'Price floor'!{PF_PRICE}"
PF_PROFIT_X = f"'Price floor'!{PF_PROFIT}"


# ── Helpers ───────────────────────────────────────────────────────────────
def put(ws, ref, value=None, *, font=None, fill=None, fmt=None, al=None,
        bottom=None, top=None):
    c = ws[ref]
    if value is not None:
        c.value = value
    if font is not None:
        c.font = font
    if fill is not None:
        c.fill = fill
    if fmt is not None:
        c.number_format = fmt
    if al is not None:
        c.alignment = al
    if bottom is not None or top is not None:
        c.border = Border(bottom=bottom or c.border.bottom, top=top or c.border.top)
    return c


def merge(ws, rng, value, **style):
    # Merge FIRST, then style every cell of the range: merge_cells resets
    # the non-anchor cells to the workbook default, so styling before the
    # merge is silently thrown away.
    ws.merge_cells(rng)
    for row in ws[rng]:
        for c in row:
            put(ws, c.coordinate, **style)
    return put(ws, rng.split(":")[0], value)


def sheet(wb, title, widths, heights, canvas_cols):
    ws = wb.create_sheet(title)
    ws.sheet_view.showGridLines = False
    ws.sheet_view.zoomScale = 100
    last = len(heights) + 6
    heights = heights + [22] * 6
    # Paint the canvas white. Fills always survive conversion; the
    # gridlines-off flag occasionally doesn't.
    for r in range(1, last + 1):
        for col in range(1, canvas_cols + 1):
            c = ws.cell(r, col)
            c.fill, c.font = FILL_PAPER, arial()
    for i, w in enumerate(widths, start=1):
        ws.column_dimensions[get_column_letter(i)].width = w
    for r, h in enumerate(heights, start=1):
        ws.row_dimensions[r].height = h
    ws.sheet_properties.tabColor = "FF111111" if title == "Price floor" else "FFD9D9D9"
    return ws


def masthead(ws, right, headline, legend, span):
    put(ws, "B2", "PRICE FLOOR SHEET", font=arial(8, True, MUTED), al=LEFT_LOW)
    put(ws, f"{right}2", "findhotstuff.com", font=arial(8, True, MUTED), al=RIGHT_LOW)
    merge(ws, f"B3:{span}3", headline, font=arial(14, True), al=LEFT, bottom=RULE_INK)
    merge(ws, f"B4:{span}4", legend, font=arial(9, color=MUTED), al=LEFT)


def eyebrow(ws, row, text):
    put(ws, f"B{row}", text, font=arial(8, True, MUTED), al=LEFT_LOW)


def field(ws, row, label, value, fmt, note=None, *, computed=False, al=RIGHT):
    """One label / value / note row, with a hairline under it."""
    for col in "BCEF":
        put(ws, f"{col}{row}", bottom=RULE_HAIR)
    put(ws, f"B{row}", label, font=arial(10), al=LEFT)
    if computed:
        put(ws, f"D{row}", value, font=arial(10), fill=FILL_COMPUTED, fmt=fmt, al=al,
            bottom=RULE_HAIR)
    else:
        put(ws, f"D{row}", value, font=arial(10), fill=FILL_PAPER, fmt=fmt, al=al,
            bottom=RULE_INK)
    if note:
        put(ws, f"F{row}", note, font=arial(9, color=MUTED), al=WRAP)


def footer(ws, row, span, text=DISCLAIMER):
    merge(ws, f"B{row}:{span}{row}", text, font=arial(9, color=MUTED), al=LEFT)


# ── Tabs ──────────────────────────────────────────────────────────────────
def start_here(wb):
    ws = sheet(wb, "Start here", PANEL_WIDTHS, [p[0] for p in PLAN], 8)
    for r, (_, kind, payload) in enumerate(PLAN, start=1):
        if kind == "headline":
            masthead(ws, "F", payload, LEGEND, "F")
        elif kind == "eyebrow":
            eyebrow(ws, r, payload)
        elif kind == "setting":
            key, label, value, fmt, _, note = payload
            assert ROW[key] == r
            # The symbol is a glyph, not a number, so it sits left.
            field(ws, r, label, value, fmt, note, al=LEFT if key == "cur" else RIGHT)
        elif kind == "total":
            for col in "BCDEF":
                put(ws, f"{col}{r}", top=RULE_INK)
            put(ws, f"B{r}", "Total % fees", font=arial(11, True), al=LEFT)
            parts = "+".join(f"$D${ROW[k]}" for k, *_ in SETTINGS if k.startswith("pct_"))
            put(ws, f"D{r}", f"={parts}", font=arial(14, True), fill=FILL_COMPUTED,
                fmt=RATE, al=RIGHT)
            put(ws, f"F{r}", "Platform + processing + offsite ads. Every floor in "
                             "this file divides by what's left.",
                font=arial(9, color=MUTED), al=WRAP)
        elif kind == "disclaimer":
            footer(ws, r, "F", payload)
    return ws


def price_floor(wb):
    heights = [8, 14, 28, 16, 8, 14, 22, 22, 8, 14, 52, 14, 22, 8, 14, 36, 104, 32, 8, 20]
    ws = sheet(wb, "Price floor", PANEL_WIDTHS, heights, 8)
    masthead(ws, "F", "What is the lowest price I can sell this at?", LEGEND, "F")

    eyebrow(ws, 6, "01  WHAT YOU TYPE")
    field(ws, 7, "What the item costs you", 6.00, MONEY,
          "Wholesale or print cost. Not including shipping.")
    field(ws, 8, "The price you charge", 12.00, MONEY,
          "Change this and watch the block below.")

    # The percentage fee applies to the PRICE, not the cost — so you solve
    # for price rather than adding the fee on. Same shape as
    # min_profitable_price() in refresh_products.py. At 100% fees or more
    # there is no floor; without the guard the division goes negative and
    # every price would read SAFE.
    put(ws, "B10", f'="02  YOUR PRICE FLOOR ("&{CUR}&")"',
        font=arial(8, True, MUTED), al=LEFT_LOW)
    merge(ws, "B11:D11",
          f'=IF({PCT}>=1,"FEES ≥ 100%",'
          f'({PF_COST}+{SHIP}+{FIXED}+{MINP})/(1-{PCT}))',
          font=arial(36, True), fill=FILL_COMPUTED, fmt=MONEY, al=LEFT, bottom=RULE_INK)
    put(ws, "F11", "Sell below this and a sale earns less than your minimum "
                   "profit — or loses money outright.",
        font=arial(9, color=MUTED), al=WRAP)

    put(ws, "B12", f'="PROFIT AT YOUR PRICE ("&{CUR}&")"',
        font=arial(8, True, MUTED), al=LEFT_LOW)
    merge(ws, "B13:D13",
          f'=IF({PF_PRICE}="","",{PF_PRICE}*(1-{PCT})-{FIXED}-{SHIP}-{PF_COST})',
          font=arial(14, True), fill=FILL_COMPUTED, fmt=MONEY, al=LEFT)

    # The verdict. RED IS THE STATIC STATE: all nine cells are painted
    # signal red unconditionally, and only the calm state is a conditional
    # format. If a converter drops the rule, the sheet can over-warn — it
    # can never hide a loss.
    #
    # Three verdicts, not two. Between break-even and the floor a sale
    # still makes money, just less than the cushion you set — calling that
    # LOSES (as v1 did) would be false.
    eyebrow(ws, 15, "03  VERDICT")
    word = (f'=IF({PF_PRICE}="","",IF({PF_PROFIT}<0,"LOSES",'
            f'IF({PF_PRICE}<{PF_FLOOR},"UNDER","SAFE")))')
    amount = f'=IF({PF_PRICE}="","—",{CUR}&TEXT(ABS({PF_PROFIT}),"#,##0.00"))'
    caption = (f'=IF({PF_PRICE}="","ENTER YOUR PRICE ABOVE",'
               f'IF({PF_PROFIT}<0,"LOST ON EVERY SALE",'
               f'IF({PF_PRICE}<{PF_FLOOR},"MADE, BUT UNDER YOUR MINIMUM",'
               f'"CLEAR ON EVERY SALE")))')
    for row, size, value in ((16, 22, word), (17, 44, amount), (18, 11, caption)):
        rng = f"B{row}:D{row}"
        merge(ws, rng, value, font=arial(size, True, PAPER), fill=FILL_SIGNAL, al=CENTER)
        # One rule per merged range. It keys off the verdict WORD, so the
        # colour and the word can never disagree; an error in B16 fails the
        # rule and leaves the block red.
        ws.conditional_formatting.add(rng, FormulaRule(
            formula=['OR($B$16="",$B$16="SAFE")'], fill=FILL_COMPUTED,
            font=Font(bold=True, color=INK)))
    put(ws, "F17", "Red is the whole point of this sheet. A 2x markup goes red "
                   "more often than anyone expects.",
        font=arial(9, color=MUTED), al=WRAP)

    footer(ws, 20, "F")
    return ws


def products(wb):
    first, last = 7, 36
    heights = [8, 14, 28, 16, 8, 28] + [20] * (last - first + 1) + [8, 20]
    ws = sheet(wb, "Your products", PRODUCT_WIDTHS, heights, 12)
    masthead(ws, "I", "Every product, checked against its own floor",
             "White columns are yours. Grey columns are worked out. Leave "
             "SHIPPING blank to use your default from Start here.", "I")

    heads = ["SKU", "NAME", "COST (YOU)", "SHIPPING (YOU)", "YOUR PRICE (YOU)",
             "FLOOR (AUTO)", "PROFIT/SALE (AUTO)", "VERDICT (AUTO)"]
    for col, h in zip("BCDEFGHI", heads):
        horiz = "left" if col in "BC" else "center" if col == "I" else "right"
        put(ws, f"{col}6", h, font=arial(8, True),
            al=Alignment(horizontal=horiz, vertical="bottom", wrap_text=True),
            bottom=RULE_INK)

    for r in range(first, last + 1):
        ship = f'IF($E{r}="",{SHIP},$E{r})'
        for col in "BCDEF":
            put(ws, f"{col}{r}", font=arial(10), fmt=MONEY if col in "DEF" else None,
                al=LEFT if col in "BC" else RIGHT, bottom=RULE_HAIR)
        put(ws, f"G{r}", f'=IF($D{r}="","",IF({PCT}>=1,"n/a",'
                         f'($D{r}+{ship}+{FIXED}+{MINP})/(1-{PCT})))',
            font=arial(10), fill=FILL_COMPUTED, fmt=MONEY, al=RIGHT, bottom=RULE_HAIR)
        put(ws, f"H{r}", f'=IF(OR($D{r}="",$F{r}=""),"",'
                         f'$F{r}*(1-{PCT})-{FIXED}-{ship}-$D{r})',
            font=arial(10), fill=FILL_COMPUTED, fmt=MONEY, al=RIGHT, bottom=RULE_HAIR)
        # Same three verdicts as the Price floor tab, at row scale. A loss
        # is written as a signed amount, so it still reads with colour off.
        put(ws, f"I{r}", f'=IF(OR($D{r}="",$F{r}=""),"",IF($H{r}<0,'
                         f'"-"&{CUR}&TEXT(ABS($H{r}),"#,##0.00"),'
                         f'IF($F{r}<$G{r},"UNDER","SAFE")))',
            font=arial(10, True), fill=FILL_COMPUTED, al=CENTER, bottom=RULE_HAIR)
    # Red chips, keyed off the verdict text: blank rows stay grey, so a
    # fresh file shows thirty empty rows and no false alarms.
    ws.conditional_formatting.add(f"I{first}:I{last}", FormulaRule(
        formula=[f'AND($I{first}<>"",$I{first}<>"SAFE")'], fill=FILL_SIGNAL,
        font=Font(bold=True, color=PAPER)))

    merge(ws, f"B{last + 2}:I{last + 2}",
          f"Add rows below row {last} and drag G, H and I down — those three "
          "are formulas, everything else you type.",
          font=arial(9, color=MUTED), al=LEFT)
    ws.freeze_panes = f"D{first}"
    return ws


def ads(wb):
    heights = [8, 14, 28, 16, 8, 14, 22, 22, 8, 14, 36, 22, 8, 20]
    ws = sheet(wb, "Ads", PANEL_WIDTHS, heights, 8)
    masthead(ws, "F", "What ads have to return before they pay for themselves",
             "Nothing to type here. Every grey cell is worked out from the "
             "Price floor tab.", "F")
    eyebrow(ws, 6, "01  FROM THE PRICE FLOOR TAB")
    field(ws, 7, "Your price", f'=IF({PF_PRICE_X}="","",{PF_PRICE_X})', MONEY,
          computed=True)
    field(ws, 8, "Profit per sale", f"={PF_PROFIT_X}", MONEY, computed=True)
    eyebrow(ws, 10, "02  BREAK-EVEN ROAS")
    merge(ws, "B11:D11", '=IF($D$8="","—",IF($D$8<=0,"n/a",$D$7/$D$8))',
          font=arial(24, True), fill=FILL_COMPUTED, fmt=ROAS, al=LEFT, bottom=RULE_INK)
    put(ws, "F11", "Every 1.00 of ad spend has to come back this many times just "
                   "to break even.", font=arial(9, color=MUTED), al=WRAP)
    merge(ws, "B12:F12",
          '=IF($D$8="","Enter your price on the Price floor tab first.",'
          'IF($D$8<=0,"Each sale makes nothing before ads, so no ad spend can '
          'pay for itself. Fix the price first.","Below this number you are donating."))',
          font=arial(10), al=LEFT)
    footer(ws, 14, "F")
    return ws


def month(wb):
    heights = [8, 14, 28, 16, 8, 14] + [22] * 6 + [8, 14, 36, 20, 8, 14, 22, 22, 8, 20]
    ws = sheet(wb, "This month", PANEL_WIDTHS, heights, 8)
    masthead(ws, "F", "Did I make money this month?", LEGEND, "F")
    eyebrow(ws, 6, "01  WHAT CAME IN AND WHAT WENT OUT")
    lines = ["Revenue", "Platform + processing fees", "Cost of goods",
             "Shipping you paid", "Refunds and chargebacks", "Ad spend"]
    notes = {"Refunds and chargebacks": "Processors usually keep the fixed fee "
                                        "on a refunded order. Count it."}
    for r, label in enumerate(lines, start=7):
        # Blank, not 0.00: a fresh file shouldn't announce BROKE EVEN.
        field(ws, r, label, None, MONEY, notes.get(label))

    put(ws, "B14", f'="02  ACTUALLY MADE ("&{CUR}&")"',
        font=arial(8, True, MUTED), al=LEFT_LOW)
    merge(ws, "B15:D15", '=IF(COUNT($D$7:$D$12)=0,"—",$D$7-$D$8-$D$9-$D$10-$D$11-$D$12)',
          font=arial(24, True), fill=FILL_COMPUTED, fmt=MONEY, al=LEFT, bottom=RULE_INK)
    merge(ws, "B16:D16",
          '=IF(COUNT($D$7:$D$12)=0,"FILL IN YOUR MONTH ABOVE",'
          'IF($B$15>0,"MADE MONEY",IF($B$15<0,"LOST MONEY","BROKE EVEN")))',
          font=arial(11, True), al=LEFT)
    # Here red is the OVERRIDE, the opposite of Price floor: a fresh month
    # is empty, and a static red block on it would be a false alarm.
    for rng in ("B15:D15", "B16:D16"):
        ws.conditional_formatting.add(rng, FormulaRule(
            formula=['AND(ISNUMBER($B$15),$B$15<0)'], fill=FILL_SIGNAL,
            font=Font(bold=True, color=PAPER)))

    eyebrow(ws, 18, "03  TAX BUCKET")
    field(ws, 19, "Set aside for tax", 0.25, "0%",
          "A bucket, not tax advice. Your rate is yours.")
    field(ws, 20, "Put this much away",
          '=IF(ISNUMBER($B$15),MAX(0,$B$15)*$D$19,"")', MONEY, computed=True)
    put(ws, "D20", font=arial(14, True))
    footer(ws, 22, "F")
    return ws


# ── Audit: the rules above, checked rather than trusted ───────────────────
XREF = re.compile(r"'([^']+)'!(\$?[A-Z]+\$?\d+)")


def _audit(wb):
    allowed = {"Start here": re.compile(r"\$D\$\d+"),
               "Price floor": re.compile(re.escape(PF_PRICE) + "|"
                                         + re.escape(PF_PROFIT))}
    for ws in wb:
        for r, dim in ws.row_dimensions.items():
            assert dim.height in HEIGHTS, f"{ws.title} row {r}: height {dim.height}"
        for row in ws.iter_rows():
            for c in row:
                where = f"{ws.title}!{c.coordinate}"
                assert c.font.name == "Arial" and not c.font.i, where
                assert c.fill.fgColor.rgb in {PAPER, COMPUTED, SIGNAL, "00000000"}, where
                assert "$" not in c.number_format and "[Red]" not in c.number_format, where
                v = c.value
                if not (isinstance(v, str) and v.startswith("=")):
                    continue
                # No currency glyph typed into any formula string.
                assert not any("$" in s for s in re.findall(r'"[^"]*"', v)), where
                # Every cross-sheet reference is one of the named ones.
                assert v.count("!") == len(XREF.findall(v)), where
                for sheet_name, ref in XREF.findall(v):
                    assert allowed[sheet_name].fullmatch(ref), f"{where}: {ref}"
    # The total must add up every % row, and only those.
    total = wb["Start here"][f"D{ROW_TOTAL}"].value
    pct_rows = {ROW[k] for k in ROW if k.startswith("pct_")}
    assert {int(n) for n in re.findall(r"\$D\$(\d+)", total)} == pct_rows, total


def build():
    wb = Workbook()
    wb.remove(wb.active)
    start_here(wb)
    price_floor(wb)
    products(wb)
    ads(wb)
    month(wb)
    wb.active = 1          # opens on the floor tab, which is the product
    _audit(wb)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    wb.save(OUT)
    print(f"wrote {OUT.relative_to(Path(__file__).parents[2])}  "
          f"({OUT.stat().st_size:,} bytes, {len(wb.sheetnames)} tabs)")


if __name__ == "__main__":
    build()
