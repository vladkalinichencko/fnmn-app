"""Builds the reader's bundled fonts into App/FNMN/Fonts.

Each family ships as four static faces (Regular, Bold, Italic, BoldItalic), so SwiftUI's bold and italic land on
real faces. Libron and Atkinson Hyperlegible Next have no Cyrillic, and CoreText's fallback for a missing glyph
keeps neither the weight nor the slant, so Cyrillic is drawn into their own files from a close donor:
Literata for Libron, Golos Text for Atkinson. Donor glyphs are scaled to the base face's x-height, and slanted
to the italic angle where the donor has no italic.

    python3 server/fonts/build_reader_fonts.py ~/Downloads/Libron_Web

Needs fontTools and brotli. Literata, Atkinson Hyperlegible Next and Golos Text come from github.com/google/fonts.
"""

import math
import sys
import tempfile
import urllib.request
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.ttLib.scaleUpem import scale_upem
from fontTools.varLib import instancer

OUT = Path(__file__).resolve().parents[2] / "App/FNMN/Fonts"
GOOGLE = "https://raw.githubusercontent.com/google/fonts/main/ofl/"
CYRILLIC = list(range(0x0400, 0x0530)) + [0x2116]
STYLES = {"Regular": (400, False), "Bold": (700, False), "Italic": (400, True), "BoldItalic": (700, True)}
HUMAN = {"Regular": "Regular", "Bold": "Bold", "Italic": "Italic", "BoldItalic": "Bold Italic"}


def download(path: str, into: Path) -> Path:
    target = into / path.replace("/", "_")
    urllib.request.urlretrieve(GOOGLE + path.replace("[", "%5B").replace("]", "%5D"), target)
    return target


def instance(variable: Path, weight: int, optical_size: float | None = None) -> TTFont:
    location = {"wght": weight} | ({"opsz": optical_size} if optical_size else {})
    return instancer.instantiateVariableFont(TTFont(variable), location, updateFontNames=True)


def name(font: TTFont, family: str, postscript: str, style: str) -> None:
    """One family of four faces, which iOS groups by the family name and the style bits."""
    table = font["name"]
    for record in list(table.names):
        if record.nameID in (16, 17, 21, 22, 25) or record.platformID == 1:
            table.removeNames(nameID=record.nameID, platformID=record.platformID)
    table.setName(family, 1, 3, 1, 0x409)
    table.setName(HUMAN[style], 2, 3, 1, 0x409)
    table.setName(f"{family} {HUMAN[style]}", 4, 3, 1, 0x409)
    table.setName(f"{postscript}-{style}", 6, 3, 1, 0x409)
    bold, italic = "Bold" in style, "Italic" in style
    font["head"].macStyle = int(bold) | int(italic) << 1
    font["OS/2"].fsSelection = (font["OS/2"].fsSelection & ~0x61) | (0x20 if bold else 0) | (0x01 if italic else 0) | (0x40 if style == "Regular" else 0)
    font["OS/2"].usWeightClass = 700 if bold else 400


def add_cyrillic(base: TTFont, donor: TTFont, slant: float) -> None:
    """Copies the donor's Cyrillic glyphs into the base face, scaled to its x-height and slanted by `slant` degrees."""
    have = set(base.getBestCmap())
    wanted = [c for c in CYRILLIC if c in donor.getBestCmap() and c not in have]
    options = subset.Options()
    options.hinting = False
    options.layout_features = []
    options.notdef_outline = False
    options.name_IDs = ["*"]
    options.drop_tables += ["GPOS", "GSUB", "GDEF", "kern", "STAT", "fvar", "gvar", "HVAR", "MVAR", "avar", "DSIG"]
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=wanted)
    subsetter.subset(donor)

    x_height = lambda font: font["OS/2"].sxHeight / font["head"].unitsPerEm
    scale_upem(donor, round(base["head"].unitsPerEm * x_height(base) / x_height(donor)))
    donor["head"].unitsPerEm = base["head"].unitsPerEm

    order = donor.getGlyphOrder()
    rename = {g: g if g == ".notdef" else "cyr." + g for g in order}
    glyphs = {rename[g]: donor["glyf"][g] for g in order}
    shear = math.tan(math.radians(slant))
    for glyph in glyphs.values():
        if glyph.isComposite():
            for component in glyph.components:
                component.glyphName = rename[component.glyphName]
                component.x = round(component.x + component.y * shear)
        elif glyph.numberOfContours > 0 and shear:
            points = glyph.coordinates
            for i, (x, y) in enumerate(points):
                points[i] = (round(x + y * shear), y)

    added = [rename[g] for g in order if g != ".notdef"]
    for glyph in added:
        base["glyf"].glyphs[glyph] = glyphs[glyph]
        base["hmtx"].metrics[glyph] = donor["hmtx"].metrics[glyph.removeprefix("cyr.")]
    base.setGlyphOrder(base.getGlyphOrder() + added)
    base["glyf"].glyphOrder = base.getGlyphOrder()
    donor_map = donor.getBestCmap()
    for table in base["cmap"].tables:
        if table.isUnicode():
            for code in wanted:
                table.cmap[code] = rename[donor_map[code]]
    base["maxp"].numGlyphs = len(base.getGlyphOrder())
    if base["post"].formatType == 2.0:
        base["post"].extraNames = []
        base["post"].mapping = {}
    base["OS/2"].ulUnicodeRange1 |= 1 << 9
    base["OS/2"].ulCodePageRange1 |= 1 << 2


def main(libron_folder: Path) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as temporary:
        cache = Path(temporary)
        literata = download("literata/Literata[opsz,wght].ttf", cache)
        literata_italic = download("literata/Literata-Italic[opsz,wght].ttf", cache)
        atkinson = download("atkinsonhyperlegiblenext/AtkinsonHyperlegibleNext[wght].ttf", cache)
        atkinson_italic = download("atkinsonhyperlegiblenext/AtkinsonHyperlegibleNext-Italic[wght].ttf", cache)
        golos = download("golostext/GolosText[wght].ttf", cache)
        for license, path in [("Literata", "literata"), ("AtkinsonHyperlegibleNext", "atkinsonhyperlegiblenext"), ("GolosText", "golostext")]:
            urllib.request.urlretrieve(f"{GOOGLE}{path}/OFL.txt", OUT / f"{license}-OFL.txt")

        for style, (weight, italic) in STYLES.items():
            # Literata at its text optical size, the size the reader sets body text at.
            face = instance(literata_italic if italic else literata, weight, 12)
            name(face, "Literata", "Literata", style)
            face.save(OUT / f"Literata-{style}.ttf")

            libron = TTFont(libron_folder / f"Libron-{style}.woff2")
            libron.flavor = None
            add_cyrillic(libron, instance(literata_italic if italic else literata, weight, 12), slant=0)
            libron.save(OUT / f"Libron-{style}.ttf")

            face = instance(atkinson_italic if italic else atkinson, weight)
            name(face, "Atkinson Hyperlegible Next", "AtkinsonHyperlegibleNext", style)
            add_cyrillic(face, instance(golos, weight), slant=-face["post"].italicAngle)
            face.save(OUT / f"AtkinsonHyperlegibleNext-{style}.ttf")
            print("built", style)


if __name__ == "__main__":
    main(Path(sys.argv[1]).expanduser())
