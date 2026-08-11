#!/usr/bin/env python3
"""Builds docs/FoodCourtTycoon-Art-Brief.pdf from the content below.
Run: python3 docs/build_art_brief.py
"""
import os
from reportlab.lib.pagesizes import LETTER
from reportlab.lib.units import inch
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_LEFT, TA_CENTER
from reportlab.platypus import (
    BaseDocTemplate, PageTemplate, Frame, NextPageTemplate,
    Paragraph, Spacer, Table, TableStyle, Image, ListFlowable, ListItem,
    PageBreak, HRFlowable, KeepTogether, FrameBreak
)
from reportlab.platypus.flowables import Flowable
from reportlab.pdfgen import canvas as pdfcanvas

HERE = os.path.dirname(os.path.abspath(__file__))
SHOTS = "/private/tmp/claude-501/-Users-roberthouston-Documents-Fable/7f393612-efbb-4f49-b081-25df31956855/scratchpad/shots"
OUT = os.path.join(HERE, "FoodCourtTycoon-Art-Brief.pdf")

# ---- Palette (editorial, not the app's dark theme -- this is a print document) ----
INK = colors.HexColor("#1E1B2E")
SUBTLE = colors.HexColor("#6B6478")
ACCENT = colors.HexColor("#E8734A")     # warm coral -- pulls from the Burger Shack counter
ACCENT_DEEP = colors.HexColor("#B84E2C")
PAPER = colors.HexColor("#FBF8F3")
RULE = colors.HexColor("#E4DCD0")
CODE_BG = colors.HexColor("#F1ECE3")
BOX_BG = colors.HexColor("#FFF3EC")

styles = getSampleStyleSheet()

def style(name, **kw):
    base = kw.pop("parent", "Normal")
    s = ParagraphStyle(name, parent=styles[base], **kw)
    styles.add(s)
    return s

style("Kicker", fontName="Helvetica-Bold", fontSize=9.5, textColor=ACCENT_DEEP,
      spaceAfter=4, leading=12, tracking=1)
style("DocTitle", fontName="Helvetica-Bold", fontSize=30, textColor=INK, leading=34,
      spaceAfter=6)
style("DocSubtitle", fontName="Helvetica", fontSize=13, textColor=SUBTLE, leading=18,
      spaceAfter=2)
style("H1", fontName="Helvetica-Bold", fontSize=17, textColor=INK, spaceBefore=22,
      spaceAfter=8, leading=21)
style("H2", fontName="Helvetica-Bold", fontSize=12.5, textColor=ACCENT_DEEP, spaceBefore=14,
      spaceAfter=5, leading=16)
style("H3", fontName="Helvetica-Bold", fontSize=10.5, textColor=INK, spaceBefore=10,
      spaceAfter=3, leading=13)
style("Body", fontName="Helvetica", fontSize=9.7, textColor=INK, leading=14.5,
      spaceAfter=7, alignment=TA_LEFT)
style("BodySmall", fontName="Helvetica", fontSize=8.7, textColor=SUBTLE, leading=12.5,
      spaceAfter=5)
style("Quote", fontName="Helvetica-Oblique", fontSize=11.5, textColor=INK, leading=17,
      spaceAfter=8, leftIndent=14, borderColor=ACCENT, borderWidth=0, spaceBefore=6)
style("Bul", fontName="Helvetica", fontSize=9.5, textColor=INK, leading=14, spaceAfter=4)
style("BulTight", fontName="Helvetica", fontSize=9, textColor=INK, leading=12.5, spaceAfter=2)
style("Mono", fontName="Courier", fontSize=8.6, textColor=INK, leading=12, backColor=CODE_BG)
style("Caption", fontName="Helvetica-Oblique", fontSize=8.3, textColor=SUBTLE, leading=11,
      spaceAfter=10, spaceBefore=4)
style("TOCEntry", fontName="Helvetica", fontSize=10, textColor=INK, leading=18)
style("TOCNum", fontName="Helvetica-Bold", fontSize=10, textColor=ACCENT_DEEP, leading=18)
style("PillLabel", fontName="Helvetica-Bold", fontSize=8, textColor=colors.white, leading=10)
style("TableHead", fontName="Helvetica-Bold", fontSize=8.3, textColor=colors.white, leading=11)
style("TableCell", fontName="Helvetica", fontSize=8.3, textColor=INK, leading=11)
style("TableCellMono", fontName="Courier", fontSize=7.8, textColor=INK, leading=10)


def P(text, s="Body"):
    return Paragraph(text, styles[s])


def spacer(h=8):
    return Spacer(1, h)


def rule(color=RULE, thickness=0.7, space_before=4, space_after=10):
    return HRFlowable(width="100%", thickness=thickness, color=color,
                       spaceBefore=space_before, spaceAfter=space_after)


def bullets(items, style_name="Bul", bullet_char="•"):
    return ListFlowable(
        [ListItem(P(t, style_name), leftIndent=6, spaceAfter=3) for t in items],
        bulletType="bullet", bulletChar=bullet_char, start=None,
        leftIndent=14, bulletFontSize=8, bulletColor=ACCENT_DEEP, spaceAfter=8,
    )


def numbered(items, style_name="Bul"):
    return ListFlowable(
        [ListItem(P(t, style_name), leftIndent=4, spaceAfter=4) for t in items],
        bulletType="1", leftIndent=16, bulletFontSize=9, bulletColor=ACCENT_DEEP,
        spaceAfter=8,
    )


class ColorChip(Flowable):
    """A small filled rounded square used as a color swatch inside table cells."""
    def __init__(self, hexval, size=13):
        super().__init__()
        self.hexval = hexval
        self.size = size
        self.width = size
        self.height = size

    def draw(self):
        c = self.canv
        c.setFillColor(colors.HexColor(self.hexval))
        c.setStrokeColor(colors.HexColor("#00000022"))
        c.roundRect(0, 0, self.size, self.size, 3, fill=1, stroke=1)


def swatch_row(label, hexval):
    return Table(
        [[ColorChip(hexval), P(f"{label}  <font face='Courier' size=7.6>{hexval}</font>",
                                "TableCell")]],
        colWidths=[16, None], style=TableStyle([
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("LEFTPADDING", (0, 0), (-1, -1), 0),
            ("TOPPADDING", (0, 0), (-1, -1), 1),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 1),
        ])
    )


def venue_palette_table():
    rows = [
        ["Venue", "Wall", "Floor", "Counter", "Accent / glow", "Sign plate"],
        ["Burger Shack", ("#2B4E6B", "#1B3348"), "#D9BE96", "#E4453A", "#F5C242", "#FFE9A8"],
        ["Sushi Bar", ("#2F4A46", "#1A2F2C"), "#C9AE86", "#3F6B5C", "#F4A9A0", "#F6E7C9"],
        ["Pizza Piazza", ("#3A2E4C", "#241C31"), "#CBB59A", "#C4462F", "#F0C24B", "#FFE6B8"],
        ["Taco Fiesta", ("#2C5E56", "#173B36"), "#E0C08A", "#E07A3C", "#F5D547", "#FFF0C2"],
        ["Dessert Dream", ("#4B3355", "#2C1E36"), "#E8D3C4", "#E88AA8", "#9BD4C8", "#FFE7F0"],
        ["Midnight Diner", ("#1E2A4A", "#101830"), "#C9C2B8", "#5B8BD9", "#F26D9C", "#D8E6FF"],
        ["Food Truck Rally", ("#6B3A2A", "#42200F"), "#B8B0A4", "#E07A3C", "#5BD6E8", "#FFEFD1"],
    ]
    header = [P(h, "TableHead") for h in rows[0]]
    data = [header]
    for r in rows[1:]:
        name, wall, floor, counter, accent, sign = r
        wall_flow = Table([[ColorChip(wall[0]), ColorChip(wall[1])]],
                           colWidths=[14, 14],
                           style=TableStyle([("LEFTPADDING", (0, 0), (-1, -1), 0),
                                              ("TOPPADDING", (0, 0), (-1, -1), 0),
                                              ("BOTTOMPADDING", (0, 0), (-1, -1), 0)]))
        data.append([
            P(f"<b>{name}</b>", "TableCell"),
            wall_flow,
            swatch_row("", floor),
            swatch_row("", counter),
            swatch_row("", accent),
            swatch_row("", sign),
        ])
    t = Table(data, colWidths=[86, 40, 76, 76, 76, 76], repeatRows=1)
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), ACCENT_DEEP),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#FBF3EC")]),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ("LEFTPADDING", (0, 0), (-1, -1), 7),
        ("LINEBELOW", (0, 0), (-1, 0), 0.5, RULE),
        ("LINEBELOW", (0, 1), (-1, -2), 0.4, RULE),
        ("BOX", (0, 0), (-1, -1), 0.6, RULE),
    ]))
    return t


def rarity_table():
    rows = [
        ["Rarity", "Ring / accent color", "Frame idea"],
        ["Common", "#B3A8C0 (muted lavender-grey)", "Plain ring, no ornament"],
        ["Rare", "Theme.gem (cyan)", "Ring gains a faceted inner bevel"],
        ["Epic", "#B07BE8 (violet)", "Ring gains a soft outer glow"],
        ["Legendary", "Theme.star (gold)", "Ring animates -- see §5.4"],
    ]
    header = [P(h, "TableHead") for h in rows[0]]
    data = [header] + [[P(c, "TableCell") for c in r] for r in rows[1:]]
    t = Table(data, colWidths=[70, 160, 200], repeatRows=1)
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), ACCENT_DEEP),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#FBF3EC")]),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ("LEFTPADDING", (0, 0), (-1, -1), 7),
        ("BOX", (0, 0), (-1, -1), 0.6, RULE),
        ("LINEBELOW", (0, 0), (-1, 0), 0.5, RULE),
    ]))
    return t


def file_table():
    rows = [
        ["File", "Owns today", "Fate in this brief"],
        ["Sources/UI/Art/CustomerSprite.swift",
         "Customer/staff figure, hairstyles, outfits, ManagerRarityFrame",
         "Rebuilt -- new figure, kept as the seeded-variation entry point"],
        ["Sources/UI/Art/VenueProps.swift",
         "Per-theme wall clutter (signs, shelves, equipment icons)",
         "Rebuilt -- becomes the per-venue scene, not a prop overlay"],
        ["Sources/UI/VenueStageView.swift",
         "Composites wall + props + floor + sign + queue + vignette",
         "Restructured to host real depth layers (§5.2)"],
        ["Sources/UI/Theme.swift (VenuePalette)",
         "The 7 venues' wall/floor/counter/accent/sign hex values",
         "Extended, not replaced -- see §6"],
        ["Sources/UI/Art/GoldenCustomerView (in ActivePlayViews.swift)",
         "The VIP/crowned-customer tap target",
         "Restyled to read as a distinct character, not a tinted regular"],
        ["Sources/UI/Art/Icons.swift, FoodSprite.swift, CoinBurst.swift",
         "HUD glyphs, food icons, payout/confetti FX",
         "OUT OF SCOPE -- do not touch (see §2)"],
    ]
    header = [P(h, "TableHead") for h in rows[0]]
    data = [header] + [[P(c, "TableCellMono" if i == 0 else "TableCell")
                          for i, c in enumerate(r)] for r in rows[1:]]
    t = Table(data, colWidths=[168, 150, 152], repeatRows=1)
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), ACCENT_DEEP),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#FBF3EC")]),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ("LEFTPADDING", (0, 0), (-1, -1), 7),
        ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("BOX", (0, 0), (-1, -1), 0.6, RULE),
        ("LINEBELOW", (0, 0), (-1, 0), 0.5, RULE),
        ("LINEBELOW", (0, 1), (-1, -2), 0.3, RULE),
    ]))
    return t


def pill(text, bg=ACCENT):
    t = Table([[P(text, "PillLabel")]], colWidths=[None])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), bg),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("LEFTPADDING", (0, 0), (-1, -1), 8),
        ("RIGHTPADDING", (0, 0), (-1, -1), 8),
        ("ROUNDEDCORNERS", [6, 6, 6, 6]),
    ]))
    return t


def box(flowables, bg=BOX_BG, border=ACCENT):
    inner = [flowables] if not isinstance(flowables, list) else flowables
    t = Table([[inner]], colWidths=[452])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), bg),
        ("BOX", (0, 0), (-1, -1), 1, border),
        ("TOPPADDING", (0, 0), (-1, -1), 10),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 10),
        ("LEFTPADDING", (0, 0), (-1, -1), 12),
        ("RIGHTPADDING", (0, 0), (-1, -1), 12),
    ]))
    return t


# ---------------------------------------------------------------------------
# Page chrome
# ---------------------------------------------------------------------------

DOC_TITLE = "Food Court Tycoon — Character & Venue Art Brief"

def draw_header_footer(c: pdfcanvas.Canvas, doc):
    c.saveState()
    page_w, page_h = LETTER
    if doc.page > 1:
        c.setFont("Helvetica", 7.6)
        c.setFillColor(SUBTLE)
        c.drawString(0.75 * inch, page_h - 0.55 * inch, DOC_TITLE.upper())
        c.drawRightString(page_w - 0.75 * inch, page_h - 0.55 * inch,
                           "Character & Venue Art — From Scratch")
        c.setStrokeColor(RULE)
        c.setLineWidth(0.6)
        c.line(0.75 * inch, page_h - 0.62 * inch, page_w - 0.75 * inch, page_h - 0.62 * inch)
        c.setFont("Helvetica", 8)
        c.setFillColor(SUBTLE)
        c.drawCentredString(page_w / 2, 0.5 * inch, str(doc.page - 1))
    c.restoreState()


def draw_cover(c: pdfcanvas.Canvas, doc):
    c.saveState()
    page_w, page_h = LETTER
    c.setFillColor(INK)
    c.rect(0, 0, page_w, page_h, fill=1, stroke=0)
    # Warm gradient-ish glow using overlapping translucent circles (reportlab has no radial fill)
    c.setFillColor(colors.HexColor("#E8734A"))
    # Low in the page, clear of the title block above -- the first version washed out the
    # orange subtitle text sitting directly in front of it.
    glow_cx, glow_cy = page_w * 0.62, page_h * 0.30
    rings = 40
    max_r = 260
    for i in range(rings, 0, -1):
        r = max_r * i / rings
        frac = i / rings
        c.setFillAlpha(0.045 * (1 - frac * frac))
        c.circle(glow_cx, glow_cy, r, fill=1, stroke=0)
    c.setFillAlpha(1)

    c.setStrokeColor(colors.HexColor("#E8734A"))
    c.setLineWidth(1.4)
    c.line(0.85 * inch, page_h - 1.55 * inch, 2.35 * inch, page_h - 1.55 * inch)

    c.setFont("Helvetica-Bold", 9.5)
    c.setFillColor(colors.HexColor("#F0A98A"))
    c.drawString(0.85 * inch, page_h - 1.3 * inch, "ART DIRECTION BRIEF")

    c.setFont("Helvetica-Bold", 30)
    c.setFillColor(colors.white)
    c.drawString(0.85 * inch, page_h - 2.15 * inch, "Food Court Tycoon")

    c.setFont("Helvetica-Bold", 20)
    c.setFillColor(colors.HexColor("#E8734A"))
    c.drawString(0.85 * inch, page_h - 2.62 * inch, "Characters & Venues, From Scratch")

    c.setFont("Helvetica", 11.5)
    c.setFillColor(colors.HexColor("#C9C3D8"))
    c.drawString(0.85 * inch, page_h - 3.05 * inch,
                 "A full replacement of the customer/staff figures and the seven venue")
    c.drawString(0.85 * inch, page_h - 3.28 * inch,
                 "backdrops — same programmatic-SwiftUI pipeline, a materially better result.")

    # Small info strip
    info = [
        ("SCOPE", "Characters + venue backgrounds only"),
        ("CONSTRAINT", "100% vector SwiftUI — zero bundled images"),
        ("VENUES", "7, each a distinct room and mood"),
        ("STATUS", "Supersedes the Aug 2026 visual-refresh pass"),
    ]
    y = page_h - 4.1 * inch
    for label, val in info:
        c.setFont("Helvetica-Bold", 8)
        c.setFillColor(colors.HexColor("#E8734A"))
        c.drawString(0.85 * inch, y, label)
        c.setFont("Helvetica", 9.6)
        c.setFillColor(colors.HexColor("#E8E4F0"))
        c.drawString(2.05 * inch, y, val)
        y -= 0.28 * inch

    c.setFont("Helvetica-Oblique", 8.6)
    c.setFillColor(colors.HexColor("#8A8298"))
    c.drawString(0.85 * inch, 0.9 * inch,
                 "Prepared from the shipping codebase — every current-state claim here is")
    c.drawString(0.85 * inch, 0.72 * inch,
                 "grounded in Sources/UI/Art/ and Sources/UI/Theme.swift, not memory.")
    c.restoreState()


# ---------------------------------------------------------------------------
# Content
# ---------------------------------------------------------------------------

story = []

# ---- TOC ----
toc_entries = [
    ("1.", "The Mandate", "2"),
    ("2.", "Scope: What This Brief Covers (and Doesn't)", "2"),
    ("3.", "The One Hard Constraint", "2"),
    ("4.", "Current State — What's Actually Live Today", "3"),
    ("5.", "Character System — Rebuild Spec", "5"),
    ("6.", "Venue Backgrounds — Rebuild Spec", "7"),
    ("7.", "The Golden Customer & VIP Critic", "9"),
    ("8.", "Motion, Performance & Accessibility", "9"),
    ("9.", "File Map", "9"),
    ("10.", "Process & Acceptance Criteria", "11"),
]
story.append(P("Contents", "H1"))
story.append(rule())
toc_rows = []
for num, title, page_num in toc_entries:
    toc_rows.append([P(num, "TOCNum"), P(title, "TOCEntry"),
                      P(page_num, "TOCNum")])
toc_table = Table(toc_rows, colWidths=[28, 392, 28])
toc_table.setStyle(TableStyle([
    ("VALIGN", (0, 0), (-1, -1), "TOP"),
    ("ALIGN", (2, 0), (2, -1), "RIGHT"),
    ("TOPPADDING", (0, 0), (-1, -1), 2),
    ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
]))
story.append(toc_table)
story.append(PageBreak())

# ---- 1. Mandate ----
story.append(P("1. The Mandate", "H1"))
story.append(rule())
story.append(P(
    "Owner verdict: <b>“the venue and character art needs sprucing up.”</b> The prior "
    "visual-refresh pass (docs/design-brief.md, shipped Aug 2026) added gradients, glow, "
    "and lighting layers on top of the existing character and backdrop shapes. That was the "
    "right call at the time — it fixed “flat and lifeless.” It did not fix "
    "“the shapes themselves are simple.” The customer figure is still four rounded "
    "rectangles and two circles; the venue backdrop is still a gradient wall with a handful of "
    "small prop icons pinned to it. This brief asks for the opposite move: throw out the "
    "current character silhouette and the current backdrop composition, and design new ones "
    "from a blank page.", "Body"))
story.append(spacer(4))
story.append(box(P(
    "<b>What “from scratch” means here:</b> the seeded-variation system "
    "(one integer seed → a whole crowd that reads as varied, not cloned) and the "
    "per-venue palette identity are worth keeping — they're proven, tested, and load-bearing "
    "elsewhere in the app (see §6). Keep those two ideas. Replace everything about how a "
    "body, a face, an outfit, a wall, and a floor are actually drawn.", "Body")))
story.append(spacer())

# ---- 2. Scope ----
story.append(P("2. Scope: What This Brief Covers (and Doesn't)", "H1"))
story.append(rule())
story.append(P("<b>In scope:</b>", "H3"))
story.append(bullets([
    "The customer/staff figure and its variation system (CustomerSprite.swift): body, face, "
    "hair, outfits, the hat, and how a seed turns those into a crowd.",
    "The manager rarity portrait frame (ManagerRarityFrame) that surrounds staff portraits in "
    "the Collection sheet and hire flows.",
    "The Golden Customer / VIP critic presentation (the special jackpot encounter).",
    "All seven venue backdrops: wall, floor, counter, hanging sign, prop dressing, and the "
    "lighting/depth treatment that ties them together (VenueProps.swift, VenueStageView.swift).",
]))
story.append(P("<b>Explicitly out of scope</b> — do not touch, do not let the redesign's "
               "logic bleed into these:", "H3"))
story.append(bullets([
    "Food/station icons (FoodSprite.swift) — fries, burgers, sushi rolls, etc. Recently "
    "reworked, not part of this complaint.",
    "HUD glyphs, tab bar icons, coin/gem iconography (Icons.swift) — separate bespoke-glyph "
    "pass already shipped and is not what “needs sprucing up” refers to.",
    "Payout/confetti/coin-burst effects (CoinBurst.swift) — juice layer, not character or "
    "venue art.",
    "Any gameplay, balance, or layout code. This is a pure art-asset brief.",
], style_name="Bul"))
story.append(P(
    "If the new character or venue style implies a food-icon or HUD-icon refresh would look "
    "better alongside it, note that as a <i>follow-up recommendation</i> at the end of the work "
    "rather than doing it inline — keep this pass reviewable as one coherent unit.", "Body"))
story.append(spacer())

# ---- 3. Hard constraint ----
story.append(P("3. The One Hard Constraint", "H1"))
story.append(rule())
story.append(P(
    "<b>Every piece of art in this game is programmatic SwiftUI vector code. There are no "
    "bundled image assets — no PNGs, no SVG files loaded at runtime, no asset catalog "
    "entries beyond the app icon. That does not change.</b> A character is a Swift function "
    "that draws paths, fills, and strokes into a Canvas; a venue backdrop is the same. This is "
    "not a legacy constraint to work around — it's *why* the seeded-variation system "
    "exists at all (a hand-drawn PNG can't be recolored and reproportioned per-seed at zero "
    "asset cost; a vector function can), and it's why the whole game is a ~40KB binary with no "
    "art pipeline, no texture atlas, no cache-miss pop-in, and no App Store size bloat as venues "
    "and rarity tiers multiply.", "Body"))
story.append(spacer(4))
story.append(P("Practically, this means the redesign has to be expressible as:", "H3"))
story.append(numbered([
    "Bezier paths, ellipses, and rounded rects composed in a SwiftUI <font face='Courier'>"
    "Canvas</font> (see the existing <font face='Courier'>p()</font> / <font face='Courier'>"
    "custom()</font> / <font face='Courier'>fill()</font> helper pattern in CustomerSprite.swift "
    "— reuse or improve this pattern, don't invent a parallel one).",
    "Gradients and radial glows via SwiftUI's native <font face='Courier'>LinearGradient</font>/"
    "<font face='Courier'>RadialGradient</font>, exactly as VenueStageView.swift already does "
    "for the wall wash and vignette.",
    "Parametrized by a small palette (5–8 hex colors per venue, or per seeded roll for a "
    "character) so recoloring for a new venue or a cosmetic skin is a data change, not new "
    "drawing code.",
]))
story.append(P(
    "A design partner more comfortable in Figma/Illustrator than Swift should still design "
    "this visually first — but every shape needs to be simple enough (bezier curves, not "
    "500-point traced outlines) that it translates to hand-written <font face='Courier'>Path"
    "</font> code without needing an SVG import pipeline the project doesn't have.", "Body"))
story.append(spacer())

# ---- 4. Current state ----
story.append(P("4. Current State — What's Actually Live Today", "H1"))
story.append(rule())
story.append(P(
    "The screenshot below is the actual current build (iPad, built-out Burger Shack board, "
    "captured this session) — not a mockup, not an old build. This is the thing being "
    "replaced.", "Body"))
story.append(spacer(6))
img_path = os.path.join(SHOTS, "current-stage-crop.png")
if os.path.exists(img_path):
    story.append(Image(img_path, width=452, height=452 * (678/1668)))
    story.append(P("Current live build: Burger Shack backdrop, six staff figures at the "
                    "counter, one Golden Customer (crowned, center-stage).", "Caption"))
story.append(P("<b>Character diagnosis:</b>", "H3"))
story.append(bullets([
    "Silhouette is a torso rounded-rect, two leg rounded-rects, and a circle head — no "
    "neck, no shoulder width variation, no hands (tools/trays aren't held, they float or are "
    "implied). Reads instantly as a placeholder figure rather than a character.",
    "All six queued figures share one pose and one scale. Variation is limited to skin/hair/"
    "shirt/pants color plus 3 hairstyles × 3 outfit cuts × a 1-in-4 hat chance — "
    "real, but shallow enough that a full counter of six reads as “six recolors,” "
    "not six people.",
    "Zero idle motion. Managers assigned to a station and customers in the queue are "
    "completely static; only the CoinBurst/serve-event layer animates.",
    "The Golden Customer is the same rig with a crown added — a jackpot moment that "
    "should feel special looks like a manager with a hat.",
]))
story.append(P("<b>Venue backdrop diagnosis:</b>", "H3"))
story.append(bullets([
    "Structurally the same room, seven times: gradient wall → radial light pool → "
    "small pinned prop icons → gradient floor → counter band → hanging sign. "
    "The only thing that changes between Burger Shack and the Midnight Diner is the hex "
    "values and which 3–4 prop glyphs get pinned to the wall.",
    "“Props” are small isolated icons (a grill, a shelf, a menu board) floating on "
    "an otherwise empty wall — there's no sense of a built room: no floor-to-wall "
    "furniture, no depth beyond one radial gradient, no signage/texture that make Sushi Bar "
    "feel like a different physical place than Taco Fiesta beyond the color swap.",
    "No ambient life: no steam, no motion, no time-of-day variation, nothing drawing the eye "
    "around the space independent of the customer queue.",
    "Counter/floor meet at a single hard gradient seam — reads as two flat planes glued "
    "together, not a continuous room.",
]))
story.append(spacer())

# ---- 5. Character rebuild spec ----
story.append(PageBreak())
story.append(P("5. Character System — Rebuild Spec", "H1"))
story.append(rule())

story.append(P("5.1 Direction", "H2"))
story.append(P(
    "Move to a proportioned, stylized figure with a genuine silhouette — the "
    "big-head-to-body ratio, rounded/soft shapes, and high color saturation common to the "
    "top-grossing casual/idle-tycoon genre (think character-select screens in mobile tycoon "
    "and cooking games broadly, not any one title specifically — the brief is a genre "
    "convention, not a reference to copy). The goal is a figure that reads clearly at "
    "48–64pt (a station-card staff badge) <i>and</i> holds up at 140–200pt "
    "(a Collection-sheet portrait or the center-stage Golden Customer), using the same base "
    "rig scaled up with more line detail rendered in at the larger size if needed.", "Body"))
story.append(spacer(4))
story.append(P("5.2 Anatomy the current rig is missing", "H2"))
story.append(bullets([
    "A neck/shoulder transition — head should not sit flush on a rectangular torso.",
    "Arms with a visible bend and hands — at minimum, one hand should be able to hold a "
    "prop (spatula, tray, cup) for staff figures, since \"what job does this person do\" is "
    "currently unreadable from the figure alone.",
    "A wider shoulder-to-hip taper so the torso reads as a body, not a rounded box.",
    "A simple 2–3 point face (eyes + a mouth curve at minimum) — the current figure "
    "appears to have no face at all in the queue view; personality has to come from "
    "somewhere other than shirt color.",
]))
story.append(P("5.3 Variation system — keep the mechanism, deepen the inputs", "H2"))
story.append(P(
    "The seeded approach (one <font face='Courier'>Int</font> seed deterministically drives "
    "every choice via <font face='Courier'>SeededRandom</font>) is correct and should not "
    "change — it's what lets the same customer look the same every time they're drawn "
    "without persisting anything, and what makes a six-person queue actually vary without "
    "art-team effort per instance. What should grow is the <i>number of independent slots</i> "
    "the seed drives, so six people at a counter stop reading as six palette swaps of one "
    "template:", "Body"))
story.append(bullets([
    "Current: skin, hair color, shirt color, pants color, 1-of-3 hairstyle, 1-of-3 outfit, "
    "1-in-4 hat.",
    "Add: body build/height variation (2–3 proportions, not just color), a face variant "
    "(2–3 expressions or feature sets), and an accessory slot independent of the hat "
    "(glasses, apron, name tag) so “no hat” isn't the default 3-in-4 case reading as "
    "the same person.",
    "Keep the venue-themed outfit hook: today a manager's outfit is generic; consider whether "
    "the rebuilt outfit set can carry a light per-venue tint or accessory (an apron color "
    "matching the venue accent, e.g.) so a Sushi Bar crowd and a Taco Fiesta crowd feel "
    "placed in their room, not interchangeable between venues.",
]))
story.append(P("5.4 Rarity portrait frame", "H2"))
story.append(P(
    "The manager rarity ring (ManagerRarityFrame) recolors per tier but is otherwise one "
    "static ring shape today. Redesign as a frame family that escalates in complexity, not "
    "just color — the whole point of a rarity system is that Legendary should be "
    "unmistakable across a room at a glance:", "Body"))
story.append(rarity_table())
story.append(spacer(4))
story.append(P(
    "“Animates” for Legendary means something cheap and static-fallback-able: a slow "
    "hue-shift shimmer or a rotating highlight along the ring, gated behind "
    "<font face='Courier'>accessibilityReduceMotion</font> exactly like every other ambient "
    "animation in this codebase (see §8).", "Body"))
story.append(spacer())

# ---- 6. Venue rebuild spec ----
story.append(PageBreak())
story.append(P("6. Venue Backgrounds — Rebuild Spec", "H1"))
story.append(rule())
story.append(P("6.1 Direction", "H2"))
story.append(P(
    "Each of the seven venues should read as a specific, furnished room with its own "
    "storytelling detail — not a recolored template with different icons pinned to it. "
    "The brief is for a genuine scene: back wall with real depth (not one flat gradient plane), "
    "furniture and equipment appropriate to that food type built into the wall rather than "
    "floating on it, and enough per-venue specificity that a screenshot of the backdrop alone "
    "(no sign, no HUD) identifies which of the seven venues it is.", "Body"))
story.append(spacer(4))
story.append(P("6.2 Depth — the room needs layers", "H2"))
story.append(P(
    "Current structure is two flat planes (wall, floor) plus a radial light wash. Rebuild as "
    "a true layered scene, back to front:", "Body"))
story.append(numbered([
    "<b>Back wall</b> — texture or paneling appropriate to the venue (tile, brick, wood "
    "slat, neon-trimmed panel for the Diner, truck-side corrugated metal for the Food Truck), "
    "not a flat gradient rectangle.",
    "<b>Built-in furniture/equipment band</b> — shelving, a menu board, hanging "
    "equipment, a pass-through window — anchored to the wall as part of the "
    "architecture, sized and positioned so it reads as built, not pinned on top.",
    "<b>Light layer</b> — keep the warm radial wash from the string lights (it works), "
    "but consider a secondary light source per venue (an open kitchen glow, a neon sign spill "
    "for the Diner, string-light color matching the venue accent) so the lighting is bespoke, "
    "not one wash recolored seven times.",
    "<b>Counter</b> — give it real thickness/depth (a front face + a top edge highlight, "
    "not a color band), and let it carry venue-appropriate texture (tile front for Sushi, "
    "weathered metal for the Food Truck).",
    "<b>Floor</b> — a material appropriate to the room (checkerboard tile for the Diner, "
    "polished concrete for the Food Truck's pavement, warm wood for Pizza Piazza) rather than "
    "a flat gradient block; the current hard seam where floor meets wall needs a real "
    "transition (a baseboard, a shadow gradient with more falloff, or both).",
]))
story.append(P("6.3 Ambient life", "H2"))
story.append(bullets([
    "Slow ambient motion appropriate to the venue: steam wisps over a hot station, a "
    "flickering neon accent on the Diner sign, a gentle string-light sway. Cheap, looping, "
    "and each one individually gated behind reduced-motion (see §8).",
    "Consider a subtle time-of-day tint keyed to the existing Happy Hour window (18:00–"
    "20:00 local, already a live game concept — see ActivePlay.happyHourStartHour in "
    "Combo.swift) so the room itself, not just a HUD multiplier, reflects that a Happy Hour "
    "is active. Optional, but ties a purely visual change to something the game already "
    "tracks.",
]))
story.append(P("6.4 The seven rooms, one line of identity each", "H2"))
story.append(P(
    "Use these as a starting point for what makes each room specific — the design pass "
    "should feel free to go further, this is a floor, not a ceiling:", "Body"))
story.append(bullets([
    "<b>Burger Shack</b> — the tutorial's starting room: diner-red vinyl, a classic "
    "string-light patio feel, unpretentious and warm.",
    "<b>Sushi Bar</b> — dark wood, a visible bar-top counter, paper lantern lighting "
    "instead of bulb string lights.",
    "<b>Pizza Piazza</b> — warm brick oven glow as a secondary light source, checkered "
    "accents, a hanging pizza-peel or ingredient rail.",
    "<b>Taco Fiesta</b> — papel-picado-style bunting instead of a plain string, bright "
    "saturated tile.",
    "<b>Dessert Dream</b> — pastel palette already distinct; lean into a display-case "
    "front on the counter and a softer, glowing light quality.",
    "<b>Midnight Diner</b> — already the night/neon palette; this is the room where a "
    "neon sign flicker and a checkerboard floor earn the most.",
    "<b>Food Truck Rally</b> — the odd one out structurally (it's a truck, not a room) "
    "— consider a serving-window frame with the truck's interior visible behind the "
    "counter and an outdoor/string-lights-on-a-lot backdrop instead of a wall.",
]))
story.append(spacer(4))
story.append(P("6.5 Palette continuity — do not discard these values", "H2"))
story.append(P(
    "The seven-venue hex palette below is not just backdrop color — station cards, the "
    "HUD accent, and the Venue Select sheet already key off <font face='Courier'>VenuePalette"
    "</font> per venue. The redesign must <b>keep these exact hues as the identity anchor</b> "
    "for each room (adding tints/shades/textures derived from them is expected and "
    "encouraged; replacing the hue family for a venue is not, since it would desync the "
    "backdrop from UI chrome elsewhere in the app that isn't part of this brief).", "Body"))
story.append(spacer(6))
story.append(venue_palette_table())
story.append(spacer(6))

# ---- 7. Golden customer ----
story.append(PageBreak())
story.append(P("7. The Golden Customer & VIP Critic", "H1"))
story.append(rule())
story.append(P(
    "Mechanically: a golden/VIP customer has a "
    f"5% base chance to appear per queue rotation once off a 90s cooldown "
    "(<font face='Courier'>ActivePlay.goldenBaseChance</font>, "
    "<font face='Courier'>goldenCooldown</font>, Combo.swift), pays out a tip scaled to "
    "current income, and has a further 5% chance of being the VIP Critic — a "
    "×10 jackpot version (<font face='Courier'>criticChance</font>, "
    "<font face='Courier'>criticMultiplier</font>). This is the single highest-anticipation "
    "random moment in the core loop, and today it's visually a crown stuck on the standard "
    "figure.", "Body"))
story.append(P(
    "Give it a distinct silhouette treatment, not just an accessory: a genuinely different "
    "outfit tier (not one drawn from the same shirt-color array), a glow/aura consistent "
    "with the Legendary rarity treatment from §5.4, and a visibly different presentation "
    "for the Critic tier specifically versus a regular Golden Customer — right now "
    "there's no visual distinction between the two at all, so a ×10 jackpot and a normal "
    "tip look identical until the number resolves.", "Body"))
story.append(spacer())

# ---- 8. Motion/perf/a11y ----
story.append(P("8. Motion, Performance & Accessibility", "H1"))
story.append(rule())
story.append(bullets([
    "The game engine ticks at 20Hz with <font face='Courier'>TimelineView</font> "
    "interpolation on top for smooth motion between ticks. Any new ambient animation "
    "(idle bob, steam, light flicker, rarity shimmer) must be driven the same way — "
    "cheap per-frame math in a <font face='Courier'>Canvas</font> or "
    "<font face='Courier'>TimelineView</font>, never a per-frame allocation, and nothing "
    "animating while its view is off-screen.",
    "Every ambient/juice animation needs a static fallback gated on "
    "<font face='Courier'>@Environment(\\.accessibilityReduceMotion)</font> — this is an "
    "existing, tested pattern in the codebase (see the prior visual-refresh work); don't "
    "introduce a new animation that skips it.",
    "Dark-theme-only: the app forces dark mode everywhere. Nothing in the new character or "
    "venue art may assume a light background will ever be visible behind or around it.",
    "Don't regress the existing accessibility-label pass on any view this touches "
    "(VenueStageView, station cards, Collection sheet) — labels and contrast ratios "
    "survive the restyle exactly as they did in the prior refresh.",
]))
story.append(spacer())

# ---- 9. File map ----
story.append(P("9. File Map", "H1"))
story.append(rule())
story.append(P(
    "What exists today, and what happens to each file in this brief. This is the actual "
    "current file layout — use it as the starting point for implementation, not as a "
    "rename target; splitting further (e.g. one file per venue) is fine if it keeps the "
    "result maintainable.", "Body"))
story.append(spacer(4))
story.append(file_table())
story.append(spacer())

# ---- 10. Process ----
story.append(PageBreak())
story.append(P("10. Process & Acceptance Criteria", "H1"))
story.append(rule())
story.append(P("10.1 How this codebase verifies art changes", "H2"))
story.append(P(
    "This project has no visual regression tooling beyond eyes-on-screenshots — that's "
    "the actual process, not a stopgap, and it's how every prior art pass (including the one "
    "this brief supersedes) was verified. Follow it:", "Body"))
story.append(numbered([
    "Build and run in the iOS Simulator after every meaningful change (<font face='Courier'>"
    "xcodebuild ... -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'</font>) and "
    "again on an iPad simulator — the stage and station-card figures render at very "
    "different sizes across the two, and a rig that only looks right on one is not done.",
    "Screenshot before making a change and after, and compare side-by-side — never batch "
    "several unverified changes together.",
    "Seed a save with a built-out board (several owned/staffed stations, a visible customer "
    "queue, at least one manager of each rarity in the Collection sheet) before screenshotting "
    "— a fresh empty save shows none of this art.",
    "Sweep one venue (or one character element) at a time end-to-end rather than "
    "changing all seven venues' wall texture, then all seven floors, etc. — easier to "
    "review, easier to revert one room if it doesn't land.",
]))
story.append(P("10.2 Definition of done", "H2"))
story.append(bullets([
    "All seven venues distinguishable from the backdrop alone, no sign/HUD visible.",
    "Character figure reads as a person (neck, shoulder taper, hands) at both station-badge "
    "scale and Collection-portrait scale.",
    "A six-person queue reads as six different people, not six recolors.",
    "Golden Customer and VIP Critic are each visually distinct from a regular staff figure "
    "and from each other.",
    "Four rarity tiers are distinguishable at a glance, not just by reading the ring color.",
    "Full existing test suite still green (this is art-only, but a build break is a build "
    "break) — <font face='Courier'>xcodebuild test</font> across the FableTests target.",
    "No new bundled image assets anywhere in the diff.",
]))
story.append(spacer(4))
story.append(box(P(
    "<b>Open question for the design pass, not pre-decided here:</b> whether the rebuilt "
    "character rig should be a genuinely new proportion system or a deepened version of the "
    "current one. This brief argues for new proportions (§5.2) because the current "
    "silhouette is the specific thing called out as dated — but if early exploration "
    "shows the existing proportions can carry the added anatomy and variation depth this "
    "brief asks for, that's a legitimate outcome too. Bring both to a checkpoint before "
    "committing to seven venues' worth of matching work.", "Body")))

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

doc = BaseDocTemplate(OUT, pagesize=LETTER,
                       leftMargin=0.75*inch, rightMargin=0.75*inch,
                       topMargin=0.85*inch, bottomMargin=0.75*inch,
                       title=DOC_TITLE, author="Claude", subject="Art direction brief")

cover_frame = Frame(0, 0, LETTER[0], LETTER[1], id="cover", showBoundary=0)
body_frame = Frame(doc.leftMargin, doc.bottomMargin,
                    doc.width, doc.height, id="body", showBoundary=0)

doc.addPageTemplates([
    PageTemplate(id="Cover", frames=[cover_frame], onPage=draw_cover),
    PageTemplate(id="Body", frames=[body_frame], onPage=draw_header_footer),
])

# Page 1 uses the "Cover" template (its onPage paints everything, no flowable content
# needed); PageBreak then switches to "Body" for the TOC and all following sections.
cover_page = [Spacer(1, 1)]
doc.build(cover_page + [NextPageTemplate("Body"), PageBreak()] + story)

print(f"Wrote {OUT}")
