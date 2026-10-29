# Builds the BITS Pilani Dubai main building (plaza, entrance, lobby, upper corridor,
# 16 identical classrooms) and exports game/assets/campus.glb for Godot.
#
# Coordinates (Blender, Z up): +Y points into the building, entrance facade at y=0.
# Godot sees these as (x, z, -y). Object names ending in "-col" get trimesh collision
# in Godot, "-colonly" become invisible colliders.
import bpy, bmesh, math, os, random
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(globals().get("__file__") or bpy.data.filepath)))
ASSETS = ROOT + "/game/assets"
TEX = ASSETS + "/tex"
os.makedirs(TEX, exist_ok=True)
random.seed(7)

# ---------------------------------------------------------------- layout
FLOOR = 1.2          # lobby ground floor height
UP = 6.2             # upper floor height
LOBBY_X = 14.0       # lobby spans x -14..14
LOBBY_Y = 32.0       # lobby spans y 0..32
LOBBY_TOP = 12.0
MEZZ_Y = 16.0        # mezzanine front edge
WING_X1 = 78.0       # classroom wing spans x 14..78
ROOM_W = 8.0
CORR_Y0, CORR_Y1 = 25.0, 29.0
NORTH_Y1, SOUTH_Y0 = 37.0, 17.0
UP_CEIL = 9.8
DOOR_A, DOOR_B, DOOR_TOP = 1.0, 2.4, 8.6   # door gap offsets inside a room, top height
BUILD_X0, BUILD_X1, BUILD_Y1, BUILD_TOP = -30.0, 78.4, 40.0, 16.0

# ---------------------------------------------------------------- reset scene
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.curves, bpy.data.images,
             bpy.data.lights, bpy.data.cameras):
    for d in list(coll):
        try:
            coll.remove(d)
        except Exception:
            pass
SCN = bpy.context.scene.collection

_names = {}
def uname(base):
    _names[base] = _names.get(base, 0) + 1
    return f"{base}{_names[base]}"

def lin(h):
    h = h.lstrip("#")
    f = lambda c: c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return tuple(f(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4))

# ---------------------------------------------------------------- textures
def save_img(name, arr):
    h, w, _ = arr.shape
    img = bpy.data.images.new(name, w, h, alpha=False)
    rgba = np.ones((h, w, 4), dtype=np.float32)
    rgba[:, :, :3] = np.clip(arr, 0, 1)
    img.pixels.foreach_set(rgba.ravel())
    img.filepath_raw = f"{TEX}/{name}.png"
    img.file_format = "PNG"
    img.save()
    return img

def wood_tex():
    W = H = 512
    rng = np.random.default_rng(1)
    arr = np.zeros((H, W, 3), np.float32)
    ph = H // 8
    x = np.arange(W)[None, :]
    for p in range(8):
        tone = np.array([0.70, 0.66, 0.60]) * (0.9 + 0.18 * rng.random())
        yy = np.arange(ph)[:, None]
        grain = 0.05 * np.sin(x * 0.03 + yy * 0.7 + rng.random() * 10 + 4 * np.sin(x * 0.006 + p))
        block = tone[None, None, :] * (1 + grain + rng.normal(0, 0.02, (ph, W)))[:, :, None]
        seam = ((x[0] + rng.integers(0, W)) % W) < 2
        block[:, seam, :] *= 0.75
        block[0:2] *= 0.75
        arr[p * ph:(p + 1) * ph] = block
    return arr

def brick_tex():
    W = H = 512
    rng = np.random.default_rng(2)
    arr = np.zeros((H, W, 3), np.float32) + np.array([0.58, 0.55, 0.52])
    bh, bw = 32, 64
    for r in range(H // bh):
        off = (bw // 2) * (r % 2)
        for c in range(-1, W // bw + 1):
            x0 = c * bw + off
            col = np.array([0.66, 0.36, 0.29]) * (0.82 + 0.3 * rng.random())
            xs = np.arange(x0 + 3, x0 + bw - 3) % W
            arr[r * bh + 3:r * bh + bh - 3][:, xs] = col
    arr *= (1 + rng.normal(0, 0.04, (H, W, 1)))
    return arr

def tile_tex(c):
    W = H = 256
    rng = np.random.default_rng(3)
    arr = np.zeros((H, W, 3), np.float32) + np.array(c)
    arr *= (1 + rng.normal(0, 0.015, (H, W, 1)))
    arr[:3] *= 0.82
    arr[:, :3] *= 0.82
    return arr

IMG_WOOD = save_img("wood", wood_tex())
IMG_BRICK = save_img("brick", brick_tex())
IMG_TILE = save_img("tile", tile_tex((0.80, 0.80, 0.78)))
IMG_GRANITE = save_img("granite", tile_tex((0.47, 0.42, 0.37)))

# ---------------------------------------------------------------- materials
_mats = {}
def mat(name, hexc="#ffffff", emit=0.0, alpha=1.0, rough=0.7, metal=0.0, img=None):
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    rgb = lin(hexc)
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit > 0:
        b.inputs["Emission Color"].default_value = (*rgb, 1)
        b.inputs["Emission Strength"].default_value = emit
    if alpha < 1:
        b.inputs["Alpha"].default_value = alpha
        for attr, val in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
            try:
                setattr(m, attr, val)
            except Exception:
                pass
    if img is not None:
        t = m.node_tree.nodes.new("ShaderNodeTexImage")
        t.image = img
        m.node_tree.links.new(t.outputs["Color"], b.inputs["Base Color"])
    _mats[name] = m
    return m

PEACH = mat("Peach", "#E6C29C")
ORANGE = mat("Orange", "#D9703C")
WHITE = mat("White", "#F2F2EF", rough=0.5)
CREAM = mat("Cream", "#EEE6D8")
NAVY = mat("Navy", "#1E2858", rough=0.4)
GLASS = mat("Glass", "#22333A", alpha=0.45, rough=0.05, metal=0.4)
WINGLASS = mat("WindowGlass", "#34464F", rough=0.1, metal=0.3)
STONE = mat("Stone", "#7E7468", img=IMG_GRANITE, rough=0.3)
WOOD = mat("WoodFloor", "#ffffff", img=IMG_WOOD, rough=0.45)
BRICK = mat("Brick", "#ffffff", img=IMG_BRICK, rough=0.9)
TILE = mat("Tile", "#ffffff", img=IMG_TILE, rough=0.4)
GLOW = mat("LedGlow", "#E6FFF4", emit=1.6)
DIAMOND = mat("Diamond", "#BDB6B0", rough=0.8)
YELLOW = mat("BannerYellow", "#E8B11C")
LBLUE = mat("BannerBlue", "#7DB0E3")
RED = mat("BannerRed", "#D2263A")
BANNER_NAVY = mat("WelcomeNavy", "#2B2C6E")
GOLD = mat("Chandelier", "#FFD69A", emit=6.0)
LEAF = mat("Leaf", "#3F7A35")
TRUNK = mat("Trunk", "#7A5B3C")
SOFA_RED = mat("SofaRed", "#B21E2C")
BOARD = mat("Whiteboard", "#FBFBFB", rough=0.15)
DESK = mat("Desk", "#C9A27A")
CHAIR = mat("Chair", "#2F5DA8")
METAL = mat("Metal", "#5A5A5E", metal=0.6, rough=0.4)
POT = mat("Pot", "#202020")
PLANT = mat("Plant", "#2E6A2F")
PANEL = mat("CeilingPanel", "#FFFFFF", emit=2.5)
DOWNLIGHT = mat("Downlight", "#FFF6E8", emit=8.0)
TEAL = mat("TealSofa", "#2E6F86")
POSTER = [mat("PosterA", "#E8E2D6"), mat("PosterB", "#D8403A"), mat("PosterC", "#F0B43C")]
INVIS = mat("Invisible", "#ff00ff")

# ---------------------------------------------------------------- mesh builder
class Mesh:
    """Collects many boxes/cylinders into one object (one material)."""
    def __init__(self, name, material, col=False, colonly=False, tile=1.0):
        self.name, self.mat, self.col, self.colonly, self.tile = name, material, col, colonly, tile
        self.bm = bmesh.new()

    def hexa(self, corner):
        """corner(xi, yi, zi) -> (x, y, z); must keep the axis-aligned box orientation."""
        v = [self.bm.verts.new(corner(xi, yi, zi)) for xi in (0, 1) for yi in (0, 1) for zi in (0, 1)]
        for f in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
            self.bm.faces.new([v[i] for i in f])
        return self

    def box(self, x0, x1, y0, y1, z0, z1):
        xs, ys, zs = sorted((x0, x1)), sorted((y0, y1)), sorted((z0, z1))
        return self.hexa(lambda a, b, c: (xs[a], ys[b], zs[c]))

    def cyl(self, cx, cy, z0, z1, r, seg=16, r2=None, axis="z"):
        r2 = r if r2 is None else r2
        def P(u, v, w):
            if axis == "z":
                return (cx + u, cy + v, w)
            return (cx + u, w, cy + v)      # axis y: (cx, cy) = (x, z) centre, z0..z1 along y
        ring = lambda rr, w: [self.bm.verts.new(P(rr * math.cos(2 * math.pi * i / seg),
                                                   rr * math.sin(2 * math.pi * i / seg), w)) for i in range(seg)]
        bot, top = ring(r, z0), ring(r2, z1)
        flip = axis != "z"
        def face(vs):
            self.bm.faces.new(list(reversed(vs)) if flip else vs)
        face(list(reversed(bot)))
        face(top)
        for i in range(seg):
            j = (i + 1) % seg
            face([bot[i], bot[j], top[j], top[i]])
        return self

    def arc(self, cx, cy, z0, z1, r0, r1, a0, a1, seg=24):
        """Curved bench/wall segment (annulus slice)."""
        for i in range(seg):
            t0 = a0 + (a1 - a0) * i / seg
            t1 = a0 + (a1 - a0) * (i + 1) / seg
            def corner(xi, yi, zi, t0=t0, t1=t1):
                t = t0 if xi == 0 else t1
                r = r1 if yi == 0 else r0
                return (cx + r * math.cos(t), cy + r * math.sin(t), (z0, z1)[zi])
            # orientation check: swap so normals face out
            self.hexa(corner)
        return self

    def quad(self, pts):
        self.bm.faces.new([self.bm.verts.new(p) for p in pts])
        return self

    def done(self):
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        me.validate()
        uv = me.uv_layers.new(name="UV")
        for poly in me.polygons:
            n = poly.normal
            ax = max(range(3), key=lambda i: abs(n[i]))
            for li in poly.loop_indices:
                co = me.vertices[me.loops[li].vertex_index].co
                u, v = ((co.y, co.z), (co.x, co.z), (co.x, co.y))[ax]
                uv.data[li].uv = (u / self.tile, v / self.tile)
        suffix = "-colonly" if self.colonly else ("-col" if self.col else "")
        ob = bpy.data.objects.new(uname(self.name) + suffix, me)
        me.materials.append(self.mat)
        SCN.objects.link(ob)
        return ob

def load_font(path):
    try:
        return bpy.data.fonts.load(path, check_existing=True)
    except Exception:
        return None
F_SERIF = load_font("/System/Library/Fonts/Supplemental/Times New Roman Bold.ttf")
F_SANS = load_font("/System/Library/Fonts/Supplemental/Arial Bold.ttf")
F_BLACK = load_font("/System/Library/Fonts/Supplemental/Arial Black.ttf")

def text(body, loc, rot_deg, size, material, font, ext=0.02, align="CENTER"):
    cu = bpy.data.curves.new("txt", "FONT")
    cu.body = body
    if font:
        cu.font = font
    cu.size = size
    cu.extrude = ext
    cu.align_x = align
    cu.align_y = "CENTER"
    tmp = bpy.data.objects.new("tmp", cu)
    SCN.objects.link(tmp)
    tmp.location = loc
    tmp.rotation_euler = [math.radians(a) for a in rot_deg]
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg))
    ob = bpy.data.objects.new(uname("Text"), me)
    ob.matrix_world = tmp.matrix_world.copy()
    me.materials.clear()
    me.materials.append(material)
    SCN.objects.link(ob)
    bpy.data.objects.remove(tmp, do_unlink=True)
    bpy.data.curves.remove(cu)
    return ob

FACE_NEG_Y = (90, 0, 0)     # text readable from the front (viewer at -y)
FACE_POS_Y = (90, 0, 180)
FACE_POS_X = (90, 0, 90)
FACE_NEG_X = (90, 0, -90)

# ================================================================ PLAZA
Mesh("Plaza", BRICK, col=True, tile=3.0).box(-45, 95, -45, 0.2, -0.2, 0).done()
bounds = Mesh("PlazaBounds", INVIS, colonly=True)
bounds.box(-45, -44, -45, 1, 0, 6).box(94, 95, -45, 1, 0, 6).box(-45, 95, -45, -44, 0, 6)
bounds.done()

# grass beds + palms
grass = Mesh("Grass", mat("Grass", "#5E8F3E"), col=True, tile=2.0)
trunk = Mesh("PalmTrunk", TRUNK, col=True)
leaves = Mesh("PalmLeaves", LEAF)
def palm(x, y, h):
    trunk.cyl(x, y, 0, h, 0.34, 10, 0.24)
    for i in range(10):
        a = 2 * math.pi * i / 10 + random.random() * 0.4
        L, w, droop = 3.4 + random.random(), 0.5, 1.2 + random.random() * 0.8
        cx, cy, px, py = math.cos(a), math.sin(a), -math.sin(a), math.cos(a)
        top = (x, y, h)
        mid = (x + cx * L * 0.5, y + cy * L * 0.5, h + 0.35)
        tip = (x + cx * L, y + cy * L, h - droop)
        leaves.quad([(top[0] - px * .05, top[1] - py * .05, top[2]), (top[0] + px * .05, top[1] + py * .05, top[2]),
                     (mid[0] + px * w, mid[1] + py * w, mid[2]), (mid[0] - px * w, mid[1] - py * w, mid[2])])
        leaves.quad([(mid[0] - px * w, mid[1] - py * w, mid[2]), (mid[0] + px * w, mid[1] + py * w, mid[2]),
                     (tip[0] + px * .05, tip[1] + py * .05, tip[2]), (tip[0] - px * .05, tip[1] - py * .05, tip[2])])
for gx in (-26, 26):
    grass.box(gx - 6, gx + 6, -30, -14, 0, 0.15)
    for py_ in (-27, -17):
        palm(gx - 3, py_, 7 + random.random() * 1.5)
        palm(gx + 3, py_ + 2, 7.5 + random.random() * 1.5)
for x in range(34, 92, 9):
    palm(x, -6, 7 + random.random() * 2)
grass.done(); trunk.done(); leaves.done()

# ================================================================ ENTRANCE STEPS + PORTICO
steps = Mesh("Steps", STONE, tile=1.5)
for i in range(4):
    steps.box(-10, 10, -8 + i, -4, 0, 0.3 * (i + 1))
steps.done()
Mesh("StepsRamp", INVIS, colonly=True).hexa(
    lambda xi, yi, zi: ((-10, 10)[xi], (-8.3, -4)[yi], (-0.2, (0.0, FLOOR)[yi])[zi])).done()
Mesh("PorticoFloor", STONE, col=True, tile=1.5).box(-10, 10, -4, 0.2, 0, FLOOR).done()

canopy = Mesh("Canopy", PEACH)
canopy.box(-9.5, 9.5, -5, 0, 9, 13.2)
canopy.done()
Mesh("CanopyBand", ORANGE).box(-9.6, 9.6, -5.15, -4.95, 8.6, 9.0).box(-9.6, 9.6, -5.15, 0, 13.2, 13.5).done()
text("BITS Pilani, Dubai Campus", (0.6, -5.08, 10.1), FACE_NEG_Y, 1.05, NAVY, F_SERIF, ext=0.06)
Mesh("Emblem", NAVY).cyl(-7.4, 10.1, -5.12, -5.0, 0.62, 24, axis="y").done()
Mesh("EmblemFace", mat("EmblemGold", "#D8A23A")).cyl(-7.4, 10.1, -5.16, -5.1, 0.48, 24, axis="y").done()
# window band above the sign
wb = Mesh("CanopyWinFrame", WHITE)
wg = Mesh("CanopyWinGlass", WINGLASS)
wb.box(-6.4, 6.4, -5.06, -5.02, 11.3, 12.8)
wg.box(-6.2, 6.2, -5.1, -5.06, 11.45, 12.65)
for i in range(13):
    wb.box(-6.2 + i * 1.03 - 0.04, -6.2 + i * 1.03 + 0.04, -5.14, -5.1, 11.45, 12.65)
wb.done(); wg.done()

# pillars with WELCOME banners
pil = Mesh("Pillars", CREAM, col=True)
for px in (-7.6, 7.6):
    pil.cyl(px, -4.3, FLOOR, 9.0, 0.45, 20)
    pil.cyl(px, -4.3, 8.3, 8.75, 0.62, 20)
    pil.cyl(px, -4.3, FLOOR, 1.6, 0.6, 20)
pil.done()
ban = Mesh("WelcomeBanners", BANNER_NAVY)
stripe_o, stripe_y, stripe_b = Mesh("StripeO", ORANGE), Mesh("StripeY", YELLOW), Mesh("StripeB", LBLUE)
for px in (-7.6, 7.6):
    ban.box(px - 0.5, px + 0.5, -4.86, -4.8, 2.4, 8.2)
    stripe_o.box(px - 0.5, px + 0.5, -4.88, -4.8, 8.2, 8.32)
    stripe_y.box(px - 0.5, px + 0.5, -4.88, -4.8, 8.32, 8.44)
    stripe_b.box(px - 0.5, px + 0.5, -4.88, -4.8, 8.44, 8.56)
    for i, ch in enumerate("WELCOME"):
        text(ch, (px, -4.9, 7.65 - i * 0.78), FACE_NEG_Y, 0.62, WHITE, F_SANS, ext=0.01)
ban.done(); stripe_o.done(); stripe_y.done(); stripe_b.done()

# ================================================================ FACADE + BUILDING SHELL
shell = Mesh("Facade", PEACH, col=True, tile=2.0)
# front facade wings and above the lobby
shell.box(BUILD_X0, -7, -0.4, 0, 0, BUILD_TOP)
shell.box(7, BUILD_X1, -0.4, 0, 0, BUILD_TOP)
shell.box(-7, 7, -0.4, 0, 9, BUILD_TOP)
shell.box(-7, 7, -0.4, 0, 0, FLOOR)
# sides, back, roof
shell.box(BUILD_X0 - 0.4, BUILD_X0, 0, BUILD_Y1, 0, BUILD_TOP)
shell.box(BUILD_X1, BUILD_X1 + 0.4, 0, BUILD_Y1, 0, BUILD_TOP)
shell.box(BUILD_X0, BUILD_X1, BUILD_Y1, BUILD_Y1 + 0.4, 0, BUILD_TOP)
shell.box(BUILD_X0 - 0.4, BUILD_X1 + 0.4, -0.4, BUILD_Y1 + 0.4, BUILD_TOP, BUILD_TOP + 0.4)
shell.done()

# facade windows: orange surround, white frame, dark glass, mullion
w_or, w_wh, w_gl = Mesh("WinSurround", ORANGE), Mesh("WinFrame", WHITE), Mesh("WinGlass", WINGLASS)
xs = [x for x in range(-27, -9, 5)] + [x for x in range(12, 77, 5)]
for x in xs:
    if -11 < x < 11:
        continue
    for zc in (3.4, 7.4, 11.4):
        w_or.box(x - 1.45, x + 1.45, -0.46, -0.4, zc - 1.25, zc + 1.25)
        w_wh.box(x - 1.2, x + 1.2, -0.5, -0.46, zc - 1.0, zc + 1.0)
        w_gl.box(x - 1.08, x + 1.08, -0.53, -0.5, zc - 0.88, zc + 0.88)
        w_wh.box(x - 0.04, x + 0.04, -0.56, -0.53, zc - 0.88, zc + 0.88)
        w_wh.box(x - 1.08, x + 1.08, -0.56, -0.53, zc + 0.25, zc + 0.31)
# parapet trim with the little orange blocks
w_or.box(BUILD_X0, BUILD_X1, -0.5, -0.4, 14.6, 14.8)
x = BUILD_X0 + 0.4
while x < BUILD_X1 - 0.6:
    if not (-9.6 < x < 9.6):
        w_or.box(x, x + 0.55, -0.5, -0.4, 15.0, 15.6)
    x += 1.1
w_or.done(); w_wh.done(); w_gl.done()

# ================================================================ LOBBY
Mesh("LobbyFloor", WOOD, col=True, tile=4.0).box(-LOBBY_X, LOBBY_X, 0, LOBBY_Y, FLOOR - 0.2, FLOOR).done()
lw = Mesh("LobbyWalls", WHITE, col=True, tile=2.0)
lw.box(-LOBBY_X - 0.4, -LOBBY_X, 0, LOBBY_Y, FLOOR, LOBBY_TOP)                       # left
lw.box(LOBBY_X, LOBBY_X + 0.4, 0, CORR_Y0, FLOOR, LOBBY_TOP)                         # right, before corridor
lw.box(LOBBY_X, LOBBY_X + 0.4, CORR_Y1, LOBBY_Y, FLOOR, LOBBY_TOP)
lw.box(LOBBY_X, LOBBY_X + 0.4, CORR_Y0, CORR_Y1, FLOOR, UP)
lw.box(LOBBY_X, LOBBY_X + 0.4, CORR_Y0, CORR_Y1, UP_CEIL, LOBBY_TOP)
lw.box(-LOBBY_X, LOBBY_X, LOBBY_Y, LOBBY_Y + 0.4, FLOOR, LOBBY_TOP)                  # back
lw.box(-LOBBY_X, -7, 0, 0.3, FLOOR, LOBBY_TOP)                                     # inner front
lw.box(7, LOBBY_X, 0, 0.3, FLOOR, LOBBY_TOP)
lw.box(-7, 7, 0, 0.3, 9, LOBBY_TOP)
lw.done()
Mesh("LobbyCeiling", WHITE).box(-LOBBY_X, LOBBY_X, 0, LOBBY_Y, LOBBY_TOP, LOBBY_TOP + 0.3).done()

# glass curtain wall with the sliding-door gap (x -2..2)
gl = Mesh("GlassFront", GLASS, col=True)
gl.box(-7, -2, -0.05, 0.05, FLOOR, 9).box(2, 7, -0.05, 0.05, FLOOR, 9).box(-2, 2, -0.05, 0.05, 4.0, 9)
gl.done()
mull = Mesh("GlassMullions", WHITE)
for gx in (-7, -5.5, -4, -2, 2, 4, 5.5, 7):
    mull.box(gx - 0.06, gx + 0.06, -0.12, 0.08, FLOOR, 9)
for gz in (4.0, 6.4, 7.6, 8.2):
    mull.box(-7, 7, -0.12, 0.08, gz - 0.05, gz + 0.05)
mull.done()
text("BITS Pilani, Dubai Campus", (0, -0.14, 6.9), FACE_NEG_Y, 0.42, WHITE, F_SERIF, ext=0.02)

# mezzanine slab (hole over the grand staircase x -2.5..2.5, y 18..28)
mz = Mesh("Mezzanine", WOOD, col=True, tile=4.0)
mz.box(-LOBBY_X, LOBBY_X, MEZZ_Y, 18, UP - 0.2, UP)
mz.box(-LOBBY_X, LOBBY_X, 28, LOBBY_Y, UP - 0.2, UP)
mz.box(-LOBBY_X, -2.5, 18, 28, UP - 0.2, UP)
mz.box(2.5, LOBBY_X, 18, 28, UP - 0.2, UP)
mz.done()
Mesh("MezzUnderside", WHITE).box(-LOBBY_X, LOBBY_X, MEZZ_Y, LOBBY_Y, UP - 0.25, UP - 0.2).done()
Mesh("Fascia", WHITE, col=True).box(-LOBBY_X, LOBBY_X, MEZZ_Y - 0.4, MEZZ_Y, 4.5, UP).done()
text("BITS Pilani, Dubai Campus", (0.7, MEZZ_Y - 0.45, 5.3), FACE_NEG_Y, 0.95, NAVY, F_SERIF, ext=0.05)
Mesh("SignHalo", mat("SignHalo", "#FFFFFF", emit=0.5)).box(-6.2, 7.6, MEZZ_Y - 0.41, MEZZ_Y - 0.4, 4.85, 5.75).done()
Mesh("LobbyEmblem", NAVY).cyl(-7.1, 5.3, MEZZ_Y - 0.5, MEZZ_Y - 0.4, 0.6, 24, axis="y").done()
Mesh("LobbyEmblemFace", _mats["EmblemGold"]).cyl(-7.1, 5.3, MEZZ_Y - 0.54, MEZZ_Y - 0.5, 0.46, 24, axis="y").done()

# railings: front edge and around the stairwell
rail_v = Mesh("Railing", WHITE)
rail_c = Mesh("RailingCol", INVIS, colonly=True)
def railing_x(x0, x1, y):
    rail_v.box(x0, x1, y - 0.06, y + 0.06, UP + 1.0, UP + 1.1)
    rail_v.box(x0, x1, y - 0.03, y + 0.03, UP + 0.15, UP + 0.2)
    x = x0
    while x <= x1:
        rail_v.box(x - 0.025, x + 0.025, y - 0.025, y + 0.025, UP, UP + 1.0)
        x += 0.3
    rail_c.box(x0, x1, y - 0.1, y + 0.1, UP, UP + 1.2)
def railing_y(y0, y1, x):
    rail_v.box(x - 0.06, x + 0.06, y0, y1, UP + 1.0, UP + 1.1)
    rail_v.box(x - 0.03, x + 0.03, y0, y1, UP + 0.15, UP + 0.2)
    y = y0
    while y <= y1:
        rail_v.box(x - 0.025, x + 0.025, y - 0.025, y + 0.025, UP, UP + 1.0)
        y += 0.3
    rail_c.box(x - 0.1, x + 0.1, y0, y1, UP, UP + 1.2)
railing_x(-LOBBY_X, LOBBY_X, MEZZ_Y + 0.1)
railing_x(-2.5, 2.5, 18.1)
railing_y(18, 28, -2.6)
railing_y(18, 28, 2.6)
rail_v.done(); rail_c.done()

# grand staircase
st = Mesh("GrandStairs", STONE, tile=1.5)
for k in range(20):
    st.box(-2.5, 2.5, 18 + 0.5 * k, 28, FLOOR, FLOOR + 0.25 * (k + 1))
st.done()
Mesh("StairRamp", INVIS, colonly=True).hexa(
    lambda xi, yi, zi: ((-2.5, 2.5)[xi], (17.5, 28)[yi], (FLOOR - 0.1, (FLOOR, UP)[yi])[zi])).done()
Mesh("StairSides", INVIS, colonly=True).box(-2.7, -2.5, 17.5, 28, FLOOR, UP).box(2.5, 2.7, 17.5, 28, FLOOR, UP).done()

# hanging banners: innovate / achieve / lead
for (bx, m, word) in ((-2.3, YELLOW, "innovate"), (0, LBLUE, "achieve"), (2.3, RED, "lead")):
    Mesh("Banner", m).box(bx - 0.95, bx + 0.95, MEZZ_Y - 0.25, MEZZ_Y - 0.2, 7.4, 11.0).done()
    text(word, (bx, MEZZ_Y - 0.28, 7.85), FACE_NEG_Y, 0.36, WHITE, F_SANS, ext=0.005)
    Mesh("BannerRod", METAL).box(bx - 0.02, bx + 0.02, MEZZ_Y - 0.24, MEZZ_Y - 0.2, 11.0, LOBBY_TOP).done()

# ring chandelier
ch = Mesh("Chandelier", GOLD)
for i, (r, z) in enumerate(((1.7, 10.9), (1.4, 10.2), (1.15, 9.5), (0.9, 8.9), (0.65, 8.4))):
    seg = 40
    for s in range(seg):
        a0, a1 = 2 * math.pi * s / seg, 2 * math.pi * (s + 1) / seg
        ch.hexa(lambda xi, yi, zi, a0=a0, a1=a1, r=r, z=z, off=i * 0.35: (
            (r + (0.04, -0.04)[yi]) * math.cos((a0, a1)[xi]) + off * 0.3,
            8 + (r + (0.04, -0.04)[yi]) * math.sin((a0, a1)[xi]),
            z + (-0.04, 0.04)[zi]))
ch.box(-0.015, 0.015, 7.985, 8.015, 10.9, LOBBY_TOP)
ch.done()

# glowing diamond walls with "medal" diamonds (faces left out on purpose)
glow_back = Mesh("DiamondGlow", GLOW)
dia = Mesh("Diamonds", DIAMOND)
medal = {0: Mesh("MedalBlue", mat("MedalBlue", "#3E6FD8", emit=0.6)),
         1: Mesh("MedalYellow", mat("MedalYellow", "#F2C230", emit=0.6)),
         2: Mesh("MedalRed", mat("MedalRed", "#E0413F", emit=0.6))}
for side in (-1, 1):
    wx = side * LOBBY_X
    inward = -side
    glow_back.box(wx + inward * 0.02, wx + inward * 0.06, 2.0, 14.0, 5.2, 11.8)
    d, sp = 0.95, 2.1
    k = 0
    for j in range(6):
        for i in range(6):
            cy = 2.9 + i * sp + (j % 2) * sp / 2
            cz = 5.9 + j * sp / 2
            if cy > 13.3 or cz > 11.2:
                continue
            target = dia
            if (i + j * 3 + (side > 0)) % 7 == 0:
                target = medal[k % 3]
                k += 1
            x0, x1 = sorted((wx + inward * 0.06, wx + inward * 0.22))
            target.hexa(lambda xi, yi, zi, cy=cy, cz=cz, x0=x0, x1=x1: (
                (x0, x1)[xi],
                cy + (((0, -d), (d, 0))[yi][zi]),
                cz + (((-d, 0), (0, d))[yi][zi])))
glow_back.done(); dia.done()
for m_ in medal.values():
    m_.done()

# pillars under the mezzanine with "quote posters"
qp = Mesh("QuotePillars", WHITE, col=True)
for px in (-10, -5, 5, 10):
    qp.box(px - 0.35, px + 0.35, MEZZ_Y - 0.9, MEZZ_Y - 0.2, FLOOR, 4.5)
qp.done()
for n, px in enumerate((-10, -5, 5, 10)):
    for k in range(3):
        Mesh("Poster", POSTER[(n + k) % 3]).box(px - 0.37, px + 0.37, MEZZ_Y - 0.93, MEZZ_Y - 0.89,
                                                FLOOR + 0.4 + k * 1.0, FLOOR + 1.3 + k * 1.0).done()

# red & white round seating (left) and teal seating (right back)
seat_w, seat_r = Mesh("SofaBase", WHITE, col=True), Mesh("SofaTop", SOFA_RED, col=True)
seat_w.arc(-9, 8, FLOOR, FLOOR + 0.45, 1.6, 2.4, math.radians(-30), math.radians(250))
seat_r.arc(-9, 8, FLOOR + 0.45, FLOOR + 0.6, 1.6, 2.4, math.radians(-30), math.radians(250))
seat_r.arc(-9, 8, FLOOR + 0.45, FLOOR + 1.1, 2.4, 2.6, math.radians(-30), math.radians(250))
seat_w.done(); seat_r.done()
Mesh("TealSofa", TEAL, col=True).arc(9, 24, FLOOR, FLOOR + 0.55, 1.5, 2.3,
                                    math.radians(90), math.radians(300)).done()

# reception desk (right) with LED strip
Mesh("Reception", WHITE, col=True).box(9.5, 13.6, 2.5, 7.5, FLOOR, FLOOR + 1.15).done()
Mesh("ReceptionLED", GLOW).box(9.44, 9.5, 2.5, 7.5, FLOOR + 0.55, FLOOR + 0.6).box(
    9.5, 13.6, 2.44, 2.5, FLOOR + 0.55, FLOOR + 0.6).done()

# plants
pots, greens = Mesh("Pots", POT, col=True), Mesh("Plants", PLANT)
for (x, y) in ((-12.8, 14), (12.8, 14), (-6, 14.4), (6, 14.4), (-12.8, 1.2), (12.8, 9.5)):
    pots.cyl(x, y, FLOOR, FLOOR + 0.5, 0.3, 12)
    greens.cyl(x, y, FLOOR + 0.5, FLOOR + 1.6, 0.45, 8, 0.15)
pots.done(); greens.done()

# wall slogan under the mezzanine
text("ENGINEER YOUR MIND", (-7, LOBBY_Y - 0.05, 3.6), FACE_NEG_Y, 0.55, NAVY, F_BLACK, ext=0.01)
text("FOR A WORLD OF POSSIBILITIES", (-7, LOBBY_Y - 0.05, 2.9), FACE_NEG_Y, 0.42, NAVY, F_BLACK, ext=0.01)
text("ATTENDANCE IS MANDATORY", (7, LOBBY_Y - 0.05, 3.3), FACE_NEG_Y, 0.45, mat("SignRed", "#C0202E"), F_BLACK, ext=0.01)

# ceiling downlights
dl = Mesh("Downlights", DOWNLIGHT)
for x in range(-12, 13, 3):
    for y in range(2, 16, 3):
        dl.cyl(x, y, LOBBY_TOP - 0.03, LOBBY_TOP, 0.13, 10)
    for y in range(17, 32, 3):
        dl.cyl(x + 1.5, y, UP - 0.28, UP - 0.25, 0.11, 10)
dl.done()

# ================================================================ UPPER FLOOR: corridor + 16 classrooms
Mesh("UpperFloor", TILE, col=True, tile=2.0).box(LOBBY_X, WING_X1, SOUTH_Y0 - 0.2, NORTH_Y1 + 0.2, UP - 0.2, UP).done()
Mesh("UpperCeiling", WHITE).box(LOBBY_X, WING_X1, SOUTH_Y0 - 0.2, NORTH_Y1 + 0.2, UP_CEIL, UP_CEIL + 0.2).done()

walls = Mesh("ClassWalls", CREAM, col=True, tile=2.0)
walls.box(LOBBY_X, WING_X1, NORTH_Y1, NORTH_Y1 + 0.2, UP, UP_CEIL)            # north outer
walls.box(LOBBY_X, WING_X1, SOUTH_Y0 - 0.2, SOUTH_Y0, UP, UP_CEIL)            # south outer
walls.box(WING_X1 - 0.2, WING_X1, SOUTH_Y0, NORTH_Y1, UP, UP_CEIL)            # corridor end
for k in range(1, 8):                                                       # partitions
    x = LOBBY_X + k * ROOM_W
    walls.box(x - 0.1, x + 0.1, CORR_Y1, NORTH_Y1, UP, UP_CEIL)
    walls.box(x - 0.1, x + 0.1, SOUTH_Y0, CORR_Y0, UP, UP_CEIL)
walls.box(LOBBY_X, LOBBY_X + 0.4, SOUTH_Y0, CORR_Y0, UP, UP_CEIL)
walls.box(LOBBY_X, LOBBY_X + 0.4, CORR_Y1, NORTH_Y1, UP, UP_CEIL)
for wy0, wy1 in ((CORR_Y1, CORR_Y1 + 0.2), (CORR_Y0 - 0.2, CORR_Y0)):       # corridor walls with door gaps
    for k in range(8):
        x0 = LOBBY_X + k * ROOM_W
        walls.box(x0, x0 + DOOR_A, wy0, wy1, UP, UP_CEIL)
        walls.box(x0 + DOOR_B, x0 + ROOM_W, wy0, wy1, UP, UP_CEIL)
        walls.box(x0 + DOOR_A, x0 + DOOR_B, wy0, wy1, DOOR_TOP, UP_CEIL)
walls.done()

# skirting stripe along corridor (navy, like the campus signage)
sk = Mesh("Skirting", NAVY)
sk.box(LOBBY_X, WING_X1, CORR_Y1 - 0.03, CORR_Y1, UP, UP + 0.15)
sk.box(LOBBY_X, WING_X1, CORR_Y0, CORR_Y0 + 0.03, UP, UP + 0.15)
sk.done()

board, frame = Mesh("Boards", BOARD), Mesh("BoardFrames", METAL)
desks, legs, chairs = Mesh("Desks", DESK, col=True), Mesh("DeskLegs", METAL), Mesh("Chairs", CHAIR)
tdesk = Mesh("TeacherDesks", mat("TeacherDesk", "#8E6A4A"), col=True)
panels = Mesh("CeilingPanels", PANEL)
proj = Mesh("Projectors", METAL)
for k in range(8):
    x0 = LOBBY_X + k * ROOM_W
    c = x0 + ROOM_W / 2
    for north in (True, False):
        # local y measured from the corridor wall (0) to the far wall (8)
        Y = (lambda d: CORR_Y1 + d) if north else (lambda d: CORR_Y0 - d)
        far = Y(8.0)
        fw = -1 if north else 1      # direction from far wall back into room
        frame.box(c - 2.6, c + 2.6, far + fw * 0.02, far + fw * 0.08, UP + 0.95, UP + 2.45)
        board.box(c - 2.5, c + 2.5, far + fw * 0.08, far + fw * 0.11, UP + 1.0, UP + 2.4)
        proj.box(c - 0.25, c + 0.25, Y(4.2), Y(4.6), UP_CEIL - 0.35, UP_CEIL - 0.15)
        tdesk.box(c + 1.4, c + 3.2, Y(6.4), Y(7.1), UP, UP + 0.8)
        for row in range(4):
            for col in (-2.6, 0, 2.6):
                dy = 1.6 + row * 1.25
                desks.box(c + col - 0.9, c + col + 0.9, Y(dy), Y(dy + 0.6), UP + 0.72, UP + 0.76)
                legs.box(c + col - 0.88, c + col - 0.84, Y(dy + 0.05), Y(dy + 0.55), UP, UP + 0.72)
                legs.box(c + col + 0.84, c + col + 0.88, Y(dy + 0.05), Y(dy + 0.55), UP, UP + 0.72)
                for sx in (-0.45, 0.45):
                    chairs.box(c + col + sx - 0.22, c + col + sx + 0.22, Y(dy - 0.55), Y(dy - 0.1), UP + 0.42, UP + 0.47)
                    chairs.box(c + col + sx - 0.22, c + col + sx + 0.22, Y(dy - 0.6), Y(dy - 0.55), UP + 0.47, UP + 0.95)
                    legs.box(c + col + sx - 0.02, c + col + sx + 0.02, Y(dy - 0.35), Y(dy - 0.31), UP, UP + 0.42)
        for py in (2.5, 5.5):
            panels.box(c - 0.9, c + 0.9, Y(py), Y(py + 0.6), UP_CEIL - 0.02, UP_CEIL)
for i in range(16):
    x = LOBBY_X + 1.5 + i * 4
    panels.box(x, x + 1.2, CORR_Y0 + 1.7, CORR_Y1 - 1.7, UP_CEIL - 0.02, UP_CEIL)
for m_ in (board, frame, desks, legs, chairs, tdesk, panels, proj):
    m_.done()

# corridor end: fake exit sign
text("EXIT?", (WING_X1 - 0.25, 27, 8.9), FACE_NEG_X, 0.4, mat("ExitGreen", "#20B05A", emit=3.0), F_BLACK, ext=0.01)

# ================================================================ export
bpy.ops.wm.save_as_mainfile(filepath=ROOT + "/blender/campus.blend")
bpy.ops.export_scene.gltf(filepath=ASSETS + "/campus.glb", export_format="GLB",
                          export_apply=True, export_lights=False, export_cameras=False)
print("objects:", len(bpy.data.objects), "exported:", os.path.getsize(ASSETS + "/campus.glb"))
