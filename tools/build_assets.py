"""Build-time asset compiler for Archon 65: src/assets -> src/gen + target/assets.

It reads:
  src/assets/sprites/static.png + static.txt   the static sprites (24 x 21 cells, 16 a row)
                                               and their names, in sprite-id order
  src/assets/sprites/combat_NN_<type>.png      a fighter's 31 sprites per icon type NN
                                               (8 cells a row): 24 animation frames,
                                               then 7 missiles
and writes:
  src/gen/palette.asm    the 256 colours        src/gen/colours.asm   palette indices
  src/gen/sprites.asm    sprite ids, boxes, the Shapeshifter tint table
  src/gen/manifest.asm   the asset files and their attic addresses
  target/assets/*        the packed sprite files, and files.txt for build.bat
Pixels with alpha < 128 are transparent. Colours are quantised into palette entries
80-255; the logo's own colours (LOGO_PAL) keep their fixed entries 40-46, which the title
cycles. Edit the PNGs freely, but keep the cell grid and the order (static.txt).
"""
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pack import pack  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_ASSETS = os.path.join(ROOT, 'src', 'assets')
SPRITE_DIR = os.path.join(SRC_ASSETS, 'sprites')
GEN = os.path.join(ROOT, 'src', 'gen')
ASSETS = os.path.join(ROOT, 'target', 'assets')

# the luminance cycle, darkest (the dark squares) to lightest (the light squares). The C64
# had to use colours; here it is a grey scale, so lighter squares visibly favour Light
LUMINANCE = [(18, 16, 30), (58, 58, 66), (98, 98, 104), (140, 140, 142), (186, 185, 180),
             (236, 234, 222)]

UI = {
    'BLACK': (0, 0, 0), 'WHITE': (255, 255, 255), 'TEXT': (240, 232, 200),
    'SHADOW': (24, 20, 16), 'GOLD': (250, 206, 80), 'LIGHT_SIDE': (255, 224, 96),
    'DARK_SIDE': (110, 150, 255), 'RED': (230, 60, 50), 'GREY': (120, 120, 128),
    'FRAME_HI': (210, 180, 110), 'FRAME': (150, 116, 60), 'FRAME_LO': (80, 58, 28),
    'BG': (10, 8, 18), 'PANEL': (30, 26, 44), 'DIM': (90, 84, 110),
}
SHADES = ['', '_HI', '_LO', '_DEEP']
# the logo's own palette entries (40-46), so the title can cycle them: 5 golds dark to
# light, the outline, the drop shadow
LOGO_FIRST = 40
LOGO_PAL = [(120, 70, 10), (190, 120, 30), (240, 190, 70), (255, 230, 140), (255, 250, 220),
            (40, 18, 4), (16, 8, 4)]
LOGO_FIXED = {c: LOGO_FIRST + i for i, c in enumerate(LOGO_PAL)}
LOGO_COLS, LOGO_ROWS = 11, 2            # the logo: tiles of 24 x 21, a 264 x 42 picture
ART_FIRST = 80
SPR_W, SPR_H = 24, 21
SHEET_COLS = 16                         # static.png: cells per row
SET_COLS = 8                            # combat_*.png: cells per row
COMBAT_SET_SPRITES = 31                 # 24 frames + 7 missile images
COMBAT_SET_BYTES = 0x4000               # one set per 16 KB in attic
SHIFTER_BODY = (172, 112, 214)          # the Shapeshifter's colour: its copies are tinted to it
TYPE_NAMES = ['UNICORN', 'WIZARD', 'ARCHER', 'GOLEM', 'VALKYRIE', 'DJINNI', 'PHOENIX', 'KNIGHT',
              'BASILISK', 'SORCERESS', 'MANTICORE', 'TROLL', 'SHAPESHIFTER', 'DRAGON', 'BANSHEE',
              'GOBLIN', 'AIR', 'FIRE', 'EARTH', 'WATER']
ATTIC_SPRITES = 0x8000000               # the sprite sheet, copied to chip RAM ($20000) at boot
ATTIC_COMBAT = 0x8020000                # combat sets, 16 KB each, copied in for every fight
ATTIC_EFFECTS = 0x8070000               # spell effect frames, copied to chip RAM at boot
FX_DIR = os.path.join(SRC_ASSETS, 'effects')
FX_W, FX_H = 32, 32                     # an effect frame: two 16-colour sprites side by side
FX_COLOURS = 15                         # per effect (nibble 0 is transparent)


# ---- PNG sheets ----------------------------------------------------------------------

def sheet_save(sprites, path, cols):
    """RGB rows (None = transparent) -> an RGBA PNG of 24 x 21 cells"""
    rows_n = (len(sprites) + cols - 1) // cols
    im = Image.new('RGBA', (cols * SPR_W, rows_n * SPR_H), (0, 0, 0, 0))
    for n, rows in enumerate(sprites):
        ox, oy = (n % cols) * SPR_W, (n // cols) * SPR_H
        for y in range(SPR_H):
            for x in range(SPR_W):
                if rows[y][x] is not None:
                    im.putpixel((ox + x, oy + y), tuple(rows[y][x]) + (255,))
    im.save(path)


def sheet_load(path, count, cols):
    """an RGBA PNG of 24 x 21 cells -> count sprites of RGB rows (None = transparent)"""
    im = Image.open(path).convert('RGBA')
    out = []
    for n in range(count):
        ox, oy = (n % cols) * SPR_W, (n // cols) * SPR_H
        rows = []
        for y in range(SPR_H):
            r = []
            for x in range(SPR_W):
                inside = ox + x < im.width and oy + y < im.height
                p = im.getpixel((ox + x, oy + y)) if inside else (0, 0, 0, 0)
                r.append(tuple(p[:3]) if p[3] >= 128 else None)
            rows.append(r)
        out.append(rows)
    return out


def combat_png(t):
    return os.path.join(SPRITE_DIR, 'combat_%02d_%s.png' % (t, TYPE_NAMES[t].lower()))


def save_sprites(static, sets):
    """static: [(name, rows)], sets: 20 lists of 31 sprites -> src/assets/sprites"""
    os.makedirs(SPRITE_DIR, exist_ok=True)
    sheet_save([r for _, r in static], os.path.join(SPRITE_DIR, 'static.png'), SHEET_COLS)
    open(os.path.join(SPRITE_DIR, 'static.txt'), 'w').write('\n'.join(n for n, _ in static) + '\n')
    for t, s in enumerate(sets):
        sheet_save(s, combat_png(t), SET_COLS)


def load_sprites():
    names = [n.strip() for n in open(os.path.join(SPRITE_DIR, 'static.txt')) if n.strip()]
    rows = sheet_load(os.path.join(SPRITE_DIR, 'static.png'), len(names), SHEET_COLS)
    sets = [sheet_load(combat_png(t), COMBAT_SET_SPRITES, SET_COLS) for t in range(20)]
    return list(zip(names, rows)), sets


# ---- generated asm ------------------------------------------------------------------

def asm_bytes(label, data, per_line=16):
    out = ['%s:' % label] if label else []
    for i in range(0, len(data), per_line):
        out.append('        .byte ' + ','.join('$%02x' % b for b in data[i:i + per_line]))
    return out


def write_gen(name, lines, what):
    head = ['; %s - generated by tools/build_assets.py: %s. Do not edit.' % (name, what), '']
    open(os.path.join(GEN, name), 'w').write('\n'.join(head + lines) + '\n')


def write_palette(colours):
    colours = list(colours) + [(0, 0, 0)] * (256 - len(colours))
    lines = ['palette_rgb:']
    for ch in range(3):
        lines += asm_bytes('', [c[ch] for c in colours])
    write_gen('palette.asm', lines, '256-colour palette, r/g/b tables')


def write_manifest(files):
    """files: [(disk name, attic address, unpacked length)]"""
    lines = ['asset_count = %d' % len(files), 'ATTIC_SPRITES = $%07x' % ATTIC_SPRITES,
             'ATTIC_COMBAT = $%07x' % ATTIC_COMBAT, 'ATTIC_EFFECTS = $%07x' % ATTIC_EFFECTS]
    lines += ['asset_name_len: .byte ' + ','.join(str(len(n)) for n, _, _ in files)]
    lines += ['asset_name_lo: .byte ' + ','.join('<_an%d' % i for i in range(len(files)))]
    lines += ['asset_name_hi: .byte ' + ','.join('>_an%d' % i for i in range(len(files)))]
    for k in range(4):
        lines += ['asset_attic%d: .byte ' % k +
                  ','.join('$%02x' % ((a >> (8 * k)) & 255) for _, a, _ in files)]
    lines += ['asset_len_lo: .byte ' + ','.join('$%02x' % (n & 255) for _, _, n in files)]
    lines += ['asset_len_hi: .byte ' + ','.join('$%02x' % (n >> 8) for _, _, n in files)]
    lines += ['_an%d: .text "%s"' % (i, n) for i, (n, _, _) in enumerate(files)]
    write_gen('manifest.asm', lines, 'packed asset files: attic addresses, unpacked lengths')
    # c1541 stores lower-case ASCII as unshifted PETSCII, which matches the upper-case .text
    open(os.path.join(ASSETS, 'files.txt'), 'w').write('\n'.join(n.lower() for n, _, _ in files) + '\n')


def mix(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def shades(c):
    return [c, mix(c, (255, 255, 255), 0.30), mix(c, (0, 0, 0), 0.35), mix(c, (0, 0, 0), 0.60)]


def base_palette():
    """the fixed part: (palette list, {name: index})"""
    pal, names = [], {}
    for name, c in UI.items():
        names['COL_' + name] = len(pal)
        pal.append(c)
    while len(pal) < 16:
        pal.append((0, 0, 0))
    for lvl, c in enumerate(LUMINANCE):
        for s, sc in zip(SHADES, shades(c)):
            names['COL_LUM%d%s' % (lvl, s)] = len(pal)
            pal.append(sc)
    while len(pal) < LOGO_FIRST:
        pal.append((0, 0, 0))
    for i, c in enumerate(LOGO_PAL):
        names['COL_LOGO%d' % i] = len(pal)
        pal.append(c)
    while len(pal) < ART_FIRST:
        pal.append((0, 0, 0))
    return pal, names


# ---- the sprites --------------------------------------------------------------------


def shifter_lut(pal):
    """256 palette indices: each art colour moved to the Shapeshifter's hue, same brightness"""
    body = SHIFTER_BODY
    out = list(range(256))
    for i in range(ART_FIRST, 256):
        r, g, b = pal[i]
        lum = (r * 3 + g * 6 + b) / 10 / 255
        want = mix((0, 0, 0), body, min(1.0, lum * 1.6)) if lum < 0.62 else \
            mix(body, (255, 255, 255), (lum - 0.62) / 0.38 * 0.8)
        out[i] = min(range(ART_FIRST, 256), key=lambda j: sum((x - y) ** 2 for x, y in zip(pal[j], want)))
    return out


# ---- palette allocation and the sheet -------------------------------------------------


def quantize(sprites, count):
    """map every art colour to one of `count` palette entries -> (colours, lookup)"""
    colours = sorted({c for rows in sprites for r in rows for c in r
                      if c is not None and c not in LOGO_FIXED})
    if len(colours) <= count:
        return colours, {c: i for i, c in enumerate(colours)}
    img = Image.new('RGB', (len(colours), 1))
    img.putdata(colours)
    q = img.quantize(colors=count, method=Image.Quantize.MEDIANCUT)
    pal = q.getpalette()[:count * 3]
    idx = list(q.getdata())
    return [tuple(pal[i * 3:i * 3 + 3]) for i in range(count)], {c: idx[i] for i, c in enumerate(colours)}


def encode(sprites, lookup):
    """RGB sprites -> (column-major bytes, 512 per sprite; [(x0, x1, y0, y1)] boxes)"""
    data = bytearray(len(sprites) * 512)
    boxes = []
    for n, rows in enumerate(sprites):
        xs, ys = [], []
        for x in range(SPR_W):
            for y in range(SPR_H):
                c = rows[y][x]
                if c is not None:
                    data[n * 512 + x * SPR_H + y] = LOGO_FIXED[c] if c in LOGO_FIXED else ART_FIRST + lookup[c]
                    xs.append(x)
                    ys.append(y)
        boxes.append((min(xs), max(xs), min(ys), max(ys)) if xs else (1, 0, 0, 0))
    return data, boxes


def write_parts(assets, prefix, data, part_size):
    """split data into loadable files packed for lib/unpack.asm (2-byte PRG header)
    -> [(name, offset, unpacked length)]; part_size < 64 KB (it unpacks into one bank)"""
    parts = []
    for i in range(0, len(data), part_size):
        name = '%s%d' % (prefix, i // part_size)
        chunk = data[i:i + part_size]
        packed = pack(chunk)
        assert len(packed) <= 0xF000, name + ' does not fit the staging buffer'
        open(os.path.join(assets, name), 'wb').write(bytes([0, 0]) + packed)
        parts.append((name, i, len(chunk)))
    return parts


def write_sprites(static, sets, lookup, assets, gen):
    data, boxes = encode([rows for _, rows in static], lookup)
    parts = write_parts(assets, 'SPRITES', data, 0xF000)
    # combat sets: 31 sprites, then their boxes as x0[32] x1[32] y0[32] y1[32]
    blob = bytearray()
    for s in sets:
        d, b = encode(s, lookup)
        b += [(1, 0, 0, 0)] * (32 - len(b))
        d += bytes(k[i] for i in range(4) for k in b)
        blob += d + bytes(COMBAT_SET_BYTES - len(d))
    combat = write_parts(assets, 'COMBAT', blob, 3 * COMBAT_SET_BYTES)
    lines = ['; sprites.asm - generated by tools/build_assets.py: sprite ids and boxes. Do not edit.', '']
    for n, (name, _) in enumerate(static):
        lines.append('SPR_%-22s= %d' % (name, n))
    lines += ['SPR_ICON                = SPR_ICON_UNICORN',
              'SPR_BARRIER             = SPR_BARRIER0_1     ; + (group * 7 + L - 1) * 2 + faded',
              'SPR_COUNT               = %d' % len(static),
              'LOGO_COLS               = %d' % LOGO_COLS,
              'LOGO_ROWS               = %d' % LOGO_ROWS,
              'SPRITES_BYTES           = %d' % len(data),
              'COMBAT_SET_SPRITES      = %d' % COMBAT_SET_SPRITES,
              'COMBAT_SET_BYTES        = $%x' % COMBAT_SET_BYTES, '']
    for k, label in enumerate(['sprite_x0', 'sprite_x1', 'sprite_y0', 'sprite_y1']):
        vals = [b[k] for b in boxes]
        lines.append(label + ':')
        for i in range(0, len(vals), 16):
            lines.append('        .byte ' + ','.join('%d' % v for v in vals[i:i + 16]))
    open(os.path.join(gen, 'sprites.asm'), 'w').write('\n'.join(lines) + '\n')
    return parts, combat


# ---- spell effects (hardware sprites) -------------------------------------------------

def load_effects():
    """[(name, delay, [frames of RGB rows])] from src/assets/effects"""
    im = Image.open(os.path.join(FX_DIR, 'effects.png')).convert('RGBA')
    out = []
    for r, line in enumerate(l.split() for l in open(os.path.join(FX_DIR, 'effects.txt')) if l.strip()):
        name, count, delay = line[0], int(line[1]), int(line[2])
        frames = []
        for c in range(count):
            frames.append([[tuple(p[:3]) if p[3] >= 128 else None
                            for p in (im.getpixel((c * FX_W + x, r * FX_H + y)) for x in range(FX_W))]
                           for y in range(FX_H)])
        out.append((name, delay, frames))
    return out


def fx_quantize(frames):
    """an effect's colours -> (15 colours, {colour: nibble 1-15})"""
    colours = sorted({c for f in frames for r in f for c in r if c is not None})
    if len(colours) <= FX_COLOURS:
        return colours, {c: i + 1 for i, c in enumerate(colours)}
    img = Image.new('RGB', (len(colours), 1))
    img.putdata(colours)
    q = img.quantize(colors=FX_COLOURS, method=Image.Quantize.MEDIANCUT)
    pal = q.getpalette()[:FX_COLOURS * 3]
    return ([tuple(pal[i * 3:i * 3 + 3]) for i in range(FX_COLOURS)],
            {c: i + 1 for c, i in zip(colours, q.getdata())})


def fx_encode(rows, lookup):
    """one frame -> 2 sprites x 32 rows x 8 bytes (left half, then right); high nibble = left pixel"""
    out = bytearray()
    for half in range(2):
        for y in range(FX_H):
            for b in range(8):
                x = half * 16 + b * 2
                pix = [lookup[rows[y][x + i]] if rows[y][x + i] is not None else 0 for i in range(2)]
                out.append(pix[0] << 4 | pix[1])
    return out


def nibble_swap(v):
    return (v & 15) << 4 | v >> 4


def write_effects(assets, gen):
    effects = load_effects()
    data = bytearray()
    lines = ['FX_COUNT                = %d' % len(effects)]
    first, counts, delays = [], [], []
    pal = [[(0, 0, 0)] * 16 for _ in effects]
    for e, (name, delay, frames) in enumerate(effects):
        colours, lookup = fx_quantize(frames)
        pal[e][1:1 + len(colours)] = colours
        first.append(len(data) // 512)
        counts.append(len(frames))
        delays.append(delay)
        for f in frames:
            data += fx_encode(f, lookup)
        lines.append('FX_%-20s= %d' % (name, e))
    lines += ['FX_BYTES                = %d' % len(data), '']
    lines += ['fx_first:  .byte ' + ','.join(map(str, first)),
              'fx_frames: .byte ' + ','.join(map(str, counts)),
              'fx_delay:  .byte ' + ','.join(map(str, delays))]
    for ch, label in enumerate(('fx_pal_r', 'fx_pal_g', 'fx_pal_b')):
        lines.append(label + ':                       ; 16 per effect, nibble-swapped for the VIC-IV')
        for e in range(len(effects)):
            lines.append('        .byte ' + ','.join('$%02x' % nibble_swap(pal[e][i][ch]) for i in range(16)))
    write_gen('effects.asm', lines, 'spell effect sprites')
    return write_parts(assets, 'EFFECTS', data, 0xF000)


def write_colours(gen, names):
    lines = ['; colours.asm - generated by tools/build_assets.py: palette indices. Do not edit.', '']
    lines += ['%-24s= %d' % (k, v) for k, v in names.items()]
    lines += ['LUM_BASE                = COL_LUM0', 'LUM_STRIDE              = 4']
    open(os.path.join(gen, 'colours.asm'), 'w').write('\n'.join(lines) + '\n')



def build():
    os.makedirs(GEN, exist_ok=True)
    os.makedirs(ASSETS, exist_ok=True)
    pal, names = base_palette()
    write_colours(GEN, names)
    static, sets = load_sprites()
    colours, lookup = quantize([rows for _, rows in static] + [r for s in sets for r in s],
                               256 - ART_FIRST)
    pal = pal[:ART_FIRST] + colours
    pal += [(0, 0, 0)] * (256 - len(pal))
    parts, combat = write_sprites(static, sets, lookup, ASSETS, GEN)
    lut = shifter_lut(pal)
    with open(os.path.join(GEN, 'sprites.asm'), 'a') as f:
        f.write('; the Shapeshifter tint: palette index -> its colour in the Shapeshifter\'s hue\n')
        f.write('shifter_lut:\n')
        for i in range(0, 256, 16):
            f.write('        .byte ' + ','.join('$%02x' % v for v in lut[i:i + 16]) + '\n')
    write_palette(pal)
    effects = write_effects(ASSETS, GEN)
    write_manifest([(n, ATTIC_SPRITES + off, ln) for n, off, ln in parts] +
                   [(n, ATTIC_COMBAT + off, ln) for n, off, ln in combat] +
                   [(n, ATTIC_EFFECTS + off, ln) for n, off, ln in effects])


if __name__ == '__main__':
    build()
