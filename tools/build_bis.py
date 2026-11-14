#!/usr/bin/env python3
"""Builds the best-in-slot gear routes: ForeverPlanner/Data/Routes/BiS.lua.

For every class, spec and faction it scores every levelling item that has a known source (quest
reward, dungeon boss drop or craft) with the spec's stat weights, picks the best item per slot for
each level band, and writes:
  - the picks (best item, plus a second choice when the best is crafted or a long detour);
  - the quest chains for picked quest rewards, as route steps (accept, objectives, turn in), so the
    addon can add the ones your levelling route doesn't already do;
  - a dungeon run for each dungeon with a picked drop or quest reward: its quests (picked up first),
    the run itself (quest objectives and the bosses that drop your items), then the hand-ins.

Data (all read as data, nothing executed):
  Polestar (GPL-3.0): addon/Polestar_ItemDB/Items.lua (Classic Era item stats),
    addon/Polestar_ItemDB/Forever.lua (Forever's item stats and where each levelling item comes from,
    derived from ForeverLevelingBiS by Thunder, MIT), addon/Polestar/Gear/SpecData.lua (stat weights per
    spec and level band), proficiencies from addon/Polestar/Gear/Weights.lua.
  forever-db (Polestar, CC BY 4.0 / GPL-3.0): quests, quest givers, objectives, prerequisites, spawns,
    NPC/object/item names and map frames, read from the Forever client.
  ForeverPlanner/Data/Routes/{Horde,Alliance}.lua: which quests the levelling route already does.

Usage: python tools/build_bis.py <polestar checkout>
"""
import collections
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lualit  # noqa: E402
from convert_polestar import lua_str, lua_val, load_frames, Coords  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'ForeverPlanner', 'Data', 'Routes', 'BiS.lua')

CLASS_BIT = {'WARRIOR': 1, 'PALADIN': 2, 'HUNTER': 4, 'ROGUE': 8, 'PRIEST': 16, 'SHAMAN': 64, 'MAGE': 128,
             'WARLOCK': 256, 'DRUID': 1024}
FACTION_CLASSES = {
    'Horde': ['WARRIOR', 'PALADIN', 'HUNTER', 'ROGUE', 'PRIEST', 'SHAMAN', 'MAGE', 'WARLOCK', 'DRUID'],
    'Alliance': ['WARRIOR', 'PALADIN', 'HUNTER', 'ROGUE', 'PRIEST', 'SHAMAN', 'MAGE', 'WARLOCK', 'DRUID'],
}
SPECS = {
    'WARRIOR': ['arms', 'fury', 'protection'], 'PALADIN': ['holy', 'protection', 'retribution'],
    'HUNTER': ['beastmastery', 'marksmanship', 'survival'], 'ROGUE': ['assassination', 'combat', 'subtlety'],
    'PRIEST': ['discipline', 'holy', 'shadow'], 'SHAMAN': ['elemental', 'enhancement', 'restoration'],
    'MAGE': ['arcane', 'fire', 'frost'], 'WARLOCK': ['affliction', 'demonology', 'destruction'],
    'DRUID': ['balance', 'feral', 'restoration'],
}
# Polestar Weights.lua, Gear.PROFICIENCY (weapon subclasses each class can train)
PROF = {
    'WARRIOR': dict(armor=3, at40=4, shield=True, dw=20, weapons={0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18}),
    'PALADIN': dict(armor=3, at40=4, shield=True, relic=7, weapons={0, 1, 4, 5, 6, 7, 8}),
    'HUNTER': dict(armor=2, at40=3, dw=20, weapons={0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18}),
    'ROGUE': dict(armor=2, dw=10, weapons={2, 3, 4, 7, 13, 15, 16, 18}),
    'PRIEST': dict(armor=1, weapons={4, 10, 15, 19}),
    'SHAMAN': dict(armor=2, at40=3, shield=True, relic=9, weapons={0, 1, 4, 5, 10, 13, 15}),
    'MAGE': dict(armor=1, weapons={7, 10, 15, 19}),
    'WARLOCK': dict(armor=1, weapons={7, 10, 15, 19}),
    'DRUID': dict(armor=2, relic=8, weapons={4, 5, 10, 13, 15}),
}
UNTOKEN = {'mpr': 'mp5', 'hpr': 'hp5'}
RANGED_INV = {15, 25, 26}
MELEE_INV = {13, 17, 21, 22}
ANY_ARMOR_INV = {2, 11, 12, 16, 23}
SCHOOLS = {'spArcane', 'spFire', 'spFrost', 'spHoly', 'spNature', 'spShadow'}
MELEE_DPS, AP_PER_DPS, OFFHAND_DPS = 0.01, 14, 0.5
SLOT_OF_INV = {1: 'Head', 2: 'Neck', 3: 'Shoulder', 5: 'Chest', 20: 'Chest', 6: 'Waist', 7: 'Legs', 8: 'Feet',
               9: 'Wrist', 10: 'Hands', 11: 'Ring', 12: 'Trinket', 16: 'Back', 15: 'Ranged', 25: 'Ranged',
               26: 'Ranged', 28: 'Ranged'}
SLOT_ORDER = ['Head', 'Neck', 'Shoulder', 'Back', 'Chest', 'Wrist', 'Hands', 'Waist', 'Legs', 'Feet', 'Ring',
              'Ring', 'Trinket', 'Trinket', 'Weapon', 'MainHand', 'OffHand', 'Ranged']
BANDS = [(10, 19), (20, 29), (30, 39), (40, 49), (50, 59), (60, 60)]
RAIDS = {'Molten Core', "Onyxia's Lair", 'Blackwing Lair', "Zul'Gurub", "Ruins of Ahn'Qiraj", "Ahn'Qiraj Temple",
         'Naxxramas', "Temple of Ahn'Qiraj"}
EXCLUDE_QUEST = re.compile(r'Armaments of (Battle|War)|Paragons of Power|Battlegear|Just Compensation|An Earnest Proposition|Anthion|Saving the Best for Last|Bonescythe', re.I)   # reputation-rank and set-upgrade rewards
DUNGEON_NAMES = {'Ragefire Chasm', 'Wailing Caverns', 'The Deadmines', 'Shadowfang Keep', 'Blackfathom Deeps', 'The Stockade',
                 'Gnomeregan', 'Razorfen Kraul', 'Scarlet Monastery', 'Razorfen Downs', 'Uldaman', "Zul'Farrak", 'Maraudon',
                 'Sunken Temple', 'Blackrock Depths', 'Blackrock Spire', 'Dire Maul', 'Scholomance', 'Stratholme',
                 'City of Dalaran', 'Ruins of Lordaeron', 'Hall of Thanes', 'Excavation Site'}
AREA_ALIASES = {133: 'Gnomeregan', 721: 'Gnomeregan', 1517: 'Uldaman', 1337: 'Uldaman', 1717: 'Razorfen Kraul',
                491: 'Razorfen Kraul', 978: "Zul'Farrak", 1176: "Zul'Farrak", 2100: 'Maraudon', 1477: 'Sunken Temple',
                1417: 'Sunken Temple', 1584: 'Blackrock Depths', 1583: 'Blackrock Spire', 2557: 'Dire Maul',
                2437: 'Ragefire Chasm', 722: 'Razorfen Downs', 796: 'Scarlet Monastery', 2017: 'Stratholme',
                2057: 'Scholomance', 209: 'Shadowfang Keep', 719: 'Blackfathom Deeps', 718: 'Wailing Caverns',
                1581: 'The Deadmines', 717: 'The Stockade'}
FACTION_DUNGEON = {'Ragefire Chasm': 'Horde', 'The Stockade': 'Alliance'}   # inside a faction's city
MIN_SCORE = 1.0          # ignore items whose stats barely count for the spec (on-use trinkets and the like)
MIN_DROP_PCT = 5.0       # rarer boss drops aren't worth planning around
DETOUR_GAIN = 1.10       # a quest off the route must beat the best on-route choice by 10%
CRAFT_GAIN = 1.10        # a crafted item must beat the best quest/drop choice by 10% to be the main pick


def dungeon_of_area(area, zones):
    """An AreaTable area -> the dungeon's name, or None for anything else (raids included)."""
    if not area:
        return None
    n = AREA_ALIASES.get(area) or zones.get(area)
    if not n or n in RAIDS:
        return None
    base = n.split(':')[0].strip()
    return base if base in DUNGEON_NAMES else None


def norm(s):
    return re.sub(r'\s+', ' ', re.sub(r'[^\w\s]', '', (s or '').lower())).strip()

# --------------------------------------------------------------------------- loading


def parse_item(s):
    m = re.match(r'^(\d+) (\d+) (\d+) (\d+) (\d+) (\d+)', s)
    if not m:
        return None
    inv, ilvl, req, q, cls, sub = map(int, m.groups())
    rec = dict(inv=inv, ilvl=ilvl, req=req, quality=q, cls=cls, sub=sub, allow=0, unique=False, stats={})
    dmin = dmax = speed = None
    for key, n in re.findall(r'([A-Za-z]+)(-?\d+)', s[m.end():]):
        n = int(n)
        if key == 'dmin':
            dmin = n
        elif key == 'dmax':
            dmax = n
        elif key == 'speed':
            speed = n
        elif key == 'cls':
            rec['allow'] = n
        elif key == 'uniq':
            rec['unique'] = n == 1
        else:
            rec['stats'][UNTOKEN.get(key, key)] = n
    if dmin is not None and dmax is not None and speed:
        rec['stats']['dps'] = round((dmin + dmax) / 2 / (speed / 1000), 1)
    return rec


def load_polestar(polestar):
    base = os.path.join(polestar, 'addon')
    items = {}
    src = open(os.path.join(base, 'Polestar_ItemDB/Items.lua'), encoding='utf-8').read()
    for args in lualit.call_args(src, 'DB.Register'):
        for k, v in args[1].items():
            items[k] = v
    fsrc = open(os.path.join(base, 'Polestar_ItemDB/Forever.lua'), encoding='utf-8').read()
    for args in lualit.call_args(fsrc, 'DB.Register'):
        for k, v in args[1].items():
            items[k] = v           # Forever's own stats over Era's
    lev = list(lualit.call_args(fsrc, 'DB.RegisterLeveling'))[0]
    meta, lev = lev[0], lev[1]
    parsed = {}
    for k, v in items.items():
        r = parse_item(v)
        if r:
            parsed[k] = r
    spec = open(os.path.join(base, 'Polestar/Gear/SpecData.lua'), encoding='utf-8').read()
    bands = lualit.assigned_table(spec, 'Gear.WEIGHT_BANDS')
    return parsed, lev, meta, bands


def load_db(polestar):
    d = os.path.join(polestar, 'forever-db/data')

    def rows(name):
        with open(os.path.join(d, name + '.jsonl'), encoding='utf-8') as f:
            for line in f:
                yield json.loads(line)
    db = {}
    db['quest'] = {r['id']: r for r in rows('quest')}
    db['start'] = collections.defaultdict(list)
    for r in rows('quest_start'):
        db['start'][r['quest']].append(r)
    db['end'] = collections.defaultdict(list)
    for r in rows('quest_end'):
        db['end'][r['quest']].append(r)
    db['obj'] = collections.defaultdict(list)
    for r in rows('quest_objective'):
        db['obj'][r['quest']].append(r)
    db['pre'] = collections.defaultdict(list)
    for r in rows('quest_prereq'):
        if not r.get('breadcrumb'):
            db['pre'][r['quest']].append(r)
    db['npc'] = {r['id']: r.get('name') for r in rows('npc') if r.get('name')}
    db['object'] = {r['id']: r.get('name') for r in rows('object') if r.get('name')}
    db['item'] = {r['id']: r.get('name') for r in rows('item') if r.get('name')}
    db['spawn'] = collections.defaultdict(list)
    for r in rows('spawn'):
        db['spawn'][(r['kind'], r['id'])].append(r)
    db['ui_map'] = list(rows('ui_map'))
    return db


def route_quests(faction):
    """Quest IDs the faction's levelling route turns in or picks up, from our converted route data."""
    src = open(os.path.join(ROOT, 'ForeverPlanner/Data/Routes/%s.lua' % faction), encoding='utf-8').read()
    turnins = set(int(x) for x in re.findall(r'\{"t",(\d+)', src))
    return turnins

# --------------------------------------------------------------------------- maps


class Maps:
    def __init__(self, db, polestar):
        self.frames = db['ui_map']
        # Where Polestar's guides put each NPC (map, x, y in the client's frame): the most reliable spot.
        self.npc = {}
        era, live = load_frames(polestar)
        coords = Coords(era, live)
        for rel in ('Polestar_Guides_Horde/Guides.lua', 'Polestar_Guides_Alliance/Guides.lua', 'Polestar_Guides/Guides.lua'):
            src = open(os.path.join(polestar, 'addon', rel), encoding='utf-8').read()
            for gd in lualit.register_calls(src):
                for st in gd.get('steps', []):
                    for g in st.get('goals', []):
                        if g.get('npc') and g.get('map') and 'x' in g and g['npc'] not in self.npc:
                            x, y = coords.to_live(g['map'], g['x'], g['y'], g.get('f'))
                            self.npc[g['npc']] = (g['map'], round(x, 1), round(y, 1))

    def place(self, cont, wx, wy):
        """World yards on a continent -> (uiMap, x%, y%). Zone frames are rectangles that overlap at the
        edges, so a city frame wins when the point is inside it, else the frame where the point sits
        most centrally."""
        best = None
        for f in self.frames:
            if f['map'] != cont:
                continue
            x = (f['left'] - wy) / (f['left'] - f['right']) * 100
            y = (f['top'] - wx) / (f['top'] - f['bottom']) * 100
            if 0 <= x <= 100 and 0 <= y <= 100:
                area = abs((f['left'] - f['right']) * (f['top'] - f['bottom']))
                city = area < 2.2e6
                key = (0 if city else 1, max(abs(x - 50), abs(y - 50)))
                if not best or key < best[0]:
                    best = (key, f['ui_map'], round(x, 1), round(y, 1))
        return best[1:] if best else None

# --------------------------------------------------------------------------- scoring


def weights_for(bands, cls, spec, level):
    b = bands.get(cls, {}).get(spec) or []
    pick = b[-1] if b else None
    for band in b:
        if level <= band['upTo']:
            pick = band
            break
    w = dict(pick['weights']) if pick else {}
    if 'dps' not in w:
        w['dps'] = AP_PER_DPS * w['ap'] if (cls == 'DRUID' and spec == 'feral' and w.get('ap')) else MELEE_DPS
    return w


def score(item, w, offhand=False):
    s = school = top = 0.0
    for k, v in item['stats'].items():
        if k == 'dps':
            if item['inv'] in RANGED_INV:
                s += w.get('rdps', 0) * v
            elif item['inv'] in MELEE_INV:
                s += w.get('dps', 0) * v * (OFFHAND_DPS if offhand else 1)
        elif k in SCHOOLS:
            school += w.get(k, 0) * v
            top = max(top, v)
        else:
            s += w.get(k, 0) * v
    if school > 0:
        wtop = max([w.get('sp', 0)] + [w.get(k, 0) for k in SCHOOLS])
        school = min(school, wtop * top)
    return s + school


def usable_level(item, cls):
    """-> the level the class can first wear it, or None if never."""
    p = PROF[cls]
    lvl = item['req']
    if item['allow'] and not (item['allow'] & CLASS_BIT[cls]):
        return None
    sub, inv = item['sub'], item['inv']
    if item['cls'] == 4 and inv not in ANY_ARMOR_INV:
        if 1 <= sub <= 4:
            if sub > p['armor']:
                if not (p.get('at40') and sub <= p['at40']):
                    return None
                lvl = max(lvl, 40)
        elif sub == 6:
            if not p.get('shield'):
                return None
        elif sub in (7, 8, 9):
            if p.get('relic') != sub:
                return None
    elif item['cls'] == 2:
        if sub in (14, 20) or sub not in p['weapons']:
            return None
        if inv == 22:
            if not p.get('dw'):
                return None
            lvl = max(lvl, p['dw'])
    elif item['cls'] not in (2, 4):
        return None
    return lvl

# --------------------------------------------------------------------------- sources


class Sources:
    def __init__(self, lev, db, faction):
        self.lev, self.db, self.faction = lev, db, faction
        self.side = 2 if faction == 'Horde' else 1
        self.quests = {}
        for qid, s in lev['quests'].items():
            head, choices, rewards, name = s.split('|', 3)
            level, req, side, zone, race, klass, dungeon = map(int, head.split())
            self.quests[qid] = dict(id=qid, level=level, req=req, side=side, zone=zone, race=race, cls=klass,
                                    dungeon=dungeon == 1, name=name)
        self.zones = lev['zones']
        self.npcs = lev['npcs']
        self.profs = lev['professions']

    def of(self, item_id, cls):
        out = []
        for tok in self.lev['src'].get(item_id, '').split():
            m = re.match(r'q(\d+)$', tok)
            if m:
                q = self.quests.get(int(m.group(1)))
                fdq = self.db['quest'].get(int(m.group(1)))
                if not q:
                    continue
                if q['side'] not in (3, self.side) and q['side'] != 0:
                    continue
                if q['cls'] and not (q['cls'] & CLASS_BIT[cls]):
                    continue
                if q['race']:
                    continue   # race-only quests: left out of faction-wide plans
                if fdq is None or not fdq.get('title'):
                    continue   # not in the Forever client's quest table
                if EXCLUDE_QUEST.search(fdq['title']) or self.zones.get(q['zone'], '') in RAIDS:
                    continue
                dname = dungeon_of_area(fdq.get('zone_area'), self.zones) or dungeon_of_area(q['zone'], self.zones)
                out.append(dict(kind='quest', quest=q['id'], level=max(q['req'], q['level'] - 2), dungeon=dname,
                                zone=q['zone']))
                continue
            m = re.match(r'd(\d+)x(\d+)z(\d+)$', tok)
            if m:
                npc, pct, zone = int(m.group(1)), int(m.group(2)) / 10, int(m.group(3))
                dname = dungeon_of_area(zone, self.zones)
                if not dname or pct < MIN_DROP_PCT or npc == 0 or FACTION_DUNGEON.get(dname, self.faction) != self.faction:
                    continue
                out.append(dict(kind='drop', npc=npc, pct=pct, zone=zone, dungeon=dname))
                continue
            m = re.match(r'c(\d+)p(\d+)s(\d+)$', tok)
            if m:
                out.append(dict(kind='craft', spell=int(m.group(1)), prof=self.profs[int(m.group(2)) - 1],
                                skill=int(m.group(3))))
        return out

# --------------------------------------------------------------------------- picking


def candidates(items, src, cls, on_route, dungeon_level):
    """item id -> (item, wear level, sources, best source kind)"""
    out = {}
    for iid in src.lev['src']:
        it = items.get(iid)
        if not it or it['inv'] not in SLOT_OF_INV and it['inv'] not in (13, 14, 17, 21, 22, 23):
            continue
        if it['quality'] < 2 and it['inv'] not in (11, 12):
            pass
        lvl = usable_level(it, cls)
        if lvl is None:
            continue
        srcs = src.of(iid, cls)
        if it['quality'] >= 4:
            srcs = [x for x in srcs if x['kind'] == 'drop']   # epics: only boss drops (quest epics are raid or reputation rewards)
        if not srcs:
            continue
        avail = []
        for s in srcs:
            if s['kind'] == 'quest':
                a = max(lvl, s['level'])
                kind = 'route' if (s['quest'] in on_route and not s['dungeon']) else ('dungeon' if s['dungeon'] else 'detour')
                if s['dungeon']:
                    a = max(a, dungeon_level.get(s['dungeon'], a))
            elif s['kind'] == 'drop':
                a = max(lvl, dungeon_level.get(s['dungeon'], lvl))
                kind = 'dungeon'
            else:
                a = max(lvl, -(-s['skill'] // 5))   # a profession reaches skill 5 x your level at most
                kind = 'craft'
            avail.append((a, kind, s))
        out[iid] = (it, avail)
    return out


def best_source(avail, maxlvl):
    rank = {'route': 0, 'detour': 1, 'dungeon': 2, 'craft': 3}
    opts = [(rank[k], a, s, k) for a, k, s in avail if a <= maxlvl]
    if not opts:
        return None
    opts.sort(key=lambda o: (o[0], o[1]))
    return opts[0]


def pick_band(cands, cls, spec, bands, lo, hi):
    w = weights_for(bands, cls, spec, hi)
    p = PROF[cls]
    by_slot = collections.defaultdict(list)
    for iid, (it, avail) in cands.items():
        bs = best_source(avail, hi)
        if not bs:
            continue
        _, a, s, kind = bs
        inv = it['inv']
        entry = dict(id=iid, kind=kind, src=s, avail=a, unique=it['unique'])
        if inv in SLOT_OF_INV:
            by_slot[SLOT_OF_INV[inv]].append((score(it, w), entry))
        if inv == 17:
            by_slot['TwoHand'].append((score(it, w), entry))
        if inv in (13, 21):
            by_slot['MainHand'].append((score(it, w), entry))
        if inv in (14, 23) or (inv == 22 and p.get('dw') and hi >= p['dw']) or \
                (inv == 13 and p.get('dw') and hi >= p['dw']):
            by_slot['OffHand'].append((score(it, w, offhand=inv in (13, 22)), entry))

    def choose(lst, exclude=()):
        lst = [x for x in lst if x[1]['id'] not in exclude and x[0] >= MIN_SCORE]
        if not lst:
            return None
        lst.sort(key=lambda x: -x[0])
        top = lst[0]
        noncraft = next((x for x in lst if x[1]['kind'] != 'craft'), None)
        onroute = next((x for x in lst if x[1]['kind'] == 'route'), None)
        main = top
        alt = None
        if top[1]['kind'] == 'craft' and noncraft and top[0] < noncraft[0] * CRAFT_GAIN:
            main = noncraft
        if main[1]['kind'] in ('detour', 'dungeon') and onroute and main[0] < onroute[0] * DETOUR_GAIN:
            main = onroute
        if main is not top:
            alt = top
        elif top[1]['kind'] == 'craft':
            alt = noncraft
        elif top[1]['kind'] in ('detour', 'dungeon'):
            alt = onroute
        return dict(best=main[1], score=round(main[0], 1), alt=alt[1] if alt else None)

    slots = []
    for slot in ['Head', 'Neck', 'Shoulder', 'Back', 'Chest', 'Wrist', 'Hands', 'Waist', 'Legs', 'Feet']:
        c = choose(by_slot[slot])
        if c:
            slots.append((slot, c))
    for slot in ('Ring', 'Trinket'):
        a = choose(by_slot[slot])
        if a:
            slots.append((slot, a))
            b = choose(by_slot[slot], exclude={a['best']['id']})
            if b:
                slots.append((slot, b))
    th = choose(by_slot['TwoHand'])
    mh = choose(by_slot['MainHand'])
    oh = choose(by_slot['OffHand'], exclude={mh['best']['id']} if mh else ())
    pair = (mh['score'] if mh else 0) + (oh['score'] if oh else 0)
    if th and th['score'] >= pair:
        slots.append(('Weapon', th))
    else:
        if mh:
            slots.append(('MainHand', mh))
        if oh:
            slots.append(('OffHand', oh))
    r = choose(by_slot['Ranged'])
    if r:
        slots.append(('Ranged', r))
    return slots

# --------------------------------------------------------------------------- route steps


class Steps:
    def __init__(self, db, maps, lev):
        self.db, self.maps, self.lev = db, maps, lev

    def where(self, kind, ident):
        if kind == 'npc' and ident in self.maps.npc:
            return self.maps.npc[ident]
        sp = self.db['spawn'].get((kind, ident))
        if not sp:
            return None
        s = sp[0]
        return self.maps.place(s['map'], s['x'], s['y'])

    ENEMY_CITIES = {'Horde': {1453, 1455, 1457}, 'Alliance': {1454, 1456, 1458}}
    faction = 'Horde'

    def giver(self, recs):
        # A quest can have givers in both factions' cities (the library quests): use your own side's.
        enemy = self.ENEMY_CITIES.get(self.faction, set())
        def ok(r):
            w = self.where(r['kind'], r['id']) if r['kind'] in ('npc', 'object') else None
            return not (w and w[0] in enemy)
        recs = sorted(recs, key=lambda r: 0 if ok(r) else 1)
        for r in recs:
            if r['kind'] == 'npc':
                return self.db['npc'].get(r['id'], 'NPC %d' % r['id']), self.where('npc', r['id'])
            if r['kind'] == 'object':
                return self.db['object'].get(r['id'], 'object'), self.where('object', r['id'])
            if r['kind'] == 'item':
                return 'the item %s' % self.db['item'].get(r['id'], r['id']), None
        return None, None

    def objectives(self, qid):
        out = []
        for o in sorted(self.db['obj'].get(qid, []), key=lambda o: o['n']):
            t = o.get('target')
            if o['kind'] == 'kill':
                txt = 'Kill %s' % self.db['npc'].get(t, 'targets')
            elif o['kind'] == 'item':
                txt = self.db['item'].get(t, 'items')
            elif o['kind'] == 'talk':
                txt = 'Talk to %s' % self.db['npc'].get(t, 'the NPC')
            elif o['kind'] == 'object':
                txt = self.db['object'].get(t, 'Click the object')
            else:
                txt = 'Complete the event'
            if (o.get('count') or 1) > 1:
                txt += ' x%d' % o['count']
            g = ['o', qid, {'i': o['n'], 'txt': txt}]
            if o['kind'] == 'kill' and t:
                w = self.where('npc', t)
                if w:
                    g[2].update(m=w[0], x=w[1], y=w[2])
            out.append(g)
        return out

    def chain(self, qid, seen=None, depth=0):
        """The quest and the quests that open it, in the order to do them."""
        seen = seen if seen is not None else set()
        if qid in seen or depth > 6 or not self.db['quest'].get(qid, {}).get('title'):
            return []
        seen.add(qid)
        pres = self.db['pre'].get(qid, [])
        order = []
        alls = [p['pre'] for p in pres if p.get('mode') != 'any']
        anys = [p['pre'] for p in pres if p.get('mode') == 'any']
        for p in alls + anys[:1]:
            order += self.chain(p, seen, depth + 1)
        order.append(qid)
        return order

    def quest_steps(self, qid, level):
        q = self.db['quest'][qid]
        title = q.get('title') or ('Quest %d' % qid)
        gname, gw = self.giver(self.db['start'].get(qid, []))
        ename, ew = self.giver(self.db['end'].get(qid, []))
        steps = []
        acc = ['a', qid, {}]
        if gw:
            acc[2].update(m=gw[0], x=gw[1], y=gw[2])
        if gname:
            acc[2]['n2'] = gname
        steps.append({'t': gname or title, 'lv': level, 'g': [acc]})
        objs = self.objectives(qid)
        if objs:
            steps.append({'t': title, 'lv': level, 'g': objs})
        tin = ['t', qid, {}]
        if ew:
            tin[2].update(m=ew[0], x=ew[1], y=ew[2])
        if ename:
            tin[2]['n2'] = ename
        if not objs and ename == gname and ew == gw:
            steps[0]['g'].append(tin)
        else:
            steps.append({'t': ename or title, 'lv': level, 'g': [tin]})
        return steps, (gw[0] if gw else (ew[0] if ew else None))

# --------------------------------------------------------------------------- writing


def merge_steps(steps):
    """Joins back-to-back steps at the same NPC (hand in one quest, pick up the next) into one."""
    out = []
    for st in steps:
        prev = out[-1] if out else None
        def spot(x):
            g = x['g'][0]
            return (g[2].get('m'), g[2].get('x'), g[2].get('y')) if len(g) > 2 else None
        if prev and prev['t'] == st['t'] and all(g[0] in ('a', 't') for g in prev['g'] + st['g']) \
                and spot(prev) == spot(st) and prev.get('cls') == st.get('cls'):
            prev['g'] = prev['g'] + st['g']
        else:
            out.append(dict(st, g=list(st['g'])))
    return out


def write_goal(g):
    kind, ident, extra = g[0], g[1], (g[2] if len(g) > 2 else {})
    parts = [lua_str(kind), lua_val(ident)]
    for k in ('i', 'txt', 'n2', 'm', 'x', 'y', 'opt'):
        if k in extra:
            parts.append('%s=%s' % (k, lua_val(extra[k])))
    return '{' + ','.join(parts) + '}'


def write_steps(steps):
    out = []
    for st in steps:
        p = ['t=%s' % lua_str(st['t']), 'lv=%d' % st['lv']]
        if st.get('n'):
            p.append('n=%s' % lua_str(st['n']))
        p.append('g={%s}' % ','.join(write_goal(g) for g in st['g']))
        out.append('  {' + ', '.join(p) + '},')
    return out


def main():
    polestar = sys.argv[1] if len(sys.argv) > 1 else '/home/claude/fitzforge/polestar'
    items, lev, meta, bands = load_polestar(polestar)
    db = load_db(polestar)
    maps = Maps(db, polestar)
    stepper = Steps(db, maps, lev)

    zones = lev['zones']
    # Each dungeon's quests (by the quest's area in the Forever client's table).
    dungeon_quests = collections.defaultdict(list)
    for qid, q in db['quest'].items():
        dn = dungeon_of_area(q.get('zone_area'), zones)
        if dn and q.get('title'):
            dungeon_quests[dn].append(qid)
    # Dungeon level: the median required level of the gear it drops, else of its quests.
    dungeon_req = collections.defaultdict(list)
    for iid, s in lev['src'].items():
        for tok in s.split():
            m = re.match(r'd(\d+)x(\d+)z(\d+)$', tok)
            dn = m and dungeon_of_area(int(m.group(3)), zones)
            if dn and iid in items:
                dungeon_req[dn].append(items[iid]['req'])
    dungeon_level = {d: sorted(v)[len(v) // 2] for d, v in dungeon_req.items() if v}
    for d, qs in dungeon_quests.items():
        if d not in dungeon_level:
            lv = sorted(db['quest'][q].get('level', 30) for q in qs)
            dungeon_level[d] = lv[len(lv) // 2]

    used_items, chains, dungeons, plans = {}, {}, {}, []
    report = []
    for faction in ('Horde', 'Alliance'):
        src = Sources(lev, db, faction)
        on_route = route_quests(faction)
        for cls in FACTION_CLASSES[faction]:
            cands_cache = candidates(items, src, cls, on_route, dungeon_level)
            for spec in SPECS[cls]:
                plan = []
                for lo, hi in BANDS:
                    slots = pick_band(cands_cache, cls, spec, bands, lo, hi)
                    entries = []
                    for slot, c in slots:
                        for role in ('best', 'alt'):
                            e = c.get(role)
                            if not e:
                                continue
                            used_items[e['id']] = e
                            s = e['src']
                            if s['kind'] == 'quest':
                                if s['dungeon']:
                                    dungeons.setdefault((faction, s['dungeon']), set()).add(('q', s['quest']))
                                elif s['quest'] not in on_route:
                                    key = (faction, s['quest'])
                                    chains[key] = max(chains.get(key, 0), e['avail'])
                            elif s['kind'] == 'drop':
                                dungeons.setdefault((faction, s['dungeon']), set()).add(('d', s['npc']))
                        entries.append((slot, c))
                    plan.append((lo, hi, entries))
                plans.append((cls, spec, faction, plan))
                n_detour = sum(1 for _, _, es in plan for _, c in es if c['best']['kind'] in ('detour', 'dungeon'))
                report.append('%s %s %s: %d picks, %d off the levelling route' % (
                    faction, cls, spec, sum(len(es) for _, _, es in plan), n_detour))

    # ---------------------------------------------------------------- quest chains
    chain_out = {}
    for (faction, qid), lvl in sorted(chains.items()):
        stepper.faction = faction
        order = stepper.chain(qid)
        steps, m = [], None
        for q in order:
            st, mm = stepper.quest_steps(q, lvl)
            steps += st
            m = m or mm
        steps = merge_steps(steps)
        chain_out[(faction, qid)] = dict(faction=faction, lv=lvl, m=m, steps=steps, title=db['quest'][qid].get('title') or str(qid))

    # ---------------------------------------------------------------- dungeon runs
    dung_out = {}
    for (faction, zname), needs in sorted(dungeons.items()):
        stepper.faction = faction
        side = 2 if faction == 'Horde' else 1
        lvl = dungeon_level.get(zname)
        qs = []
        for qid in dungeon_quests.get(zname, []):
            q = db['quest'][qid]
            if q.get('side') not in (0, 3, side) or EXCLUDE_QUEST.search(q['title']):
                continue
            if lvl and abs(q.get('level', lvl) - lvl) > 8:
                continue
            qs.append((q.get('level', 0), qid, q.get('classes', 0)))
        qs.sort()
        if lvl is None:
            lvl = qs[len(qs) // 2][0] if qs else 30
        acc_steps, turn_steps, run_goals, entrance = [], [], [], collections.Counter()
        emitted = set()
        main = {q for _, q, _ in qs}
        for _, qid, qcls in qs:
            if qid in emitted:
                continue
            for q in stepper.chain(qid)[:-1]:
                if q in db['quest'] and q not in emitted and q not in main:
                    emitted.add(q)
                    st, mm = stepper.quest_steps(q, max(lvl - 2, 1))
                    acc_steps += st
            emitted.add(qid)
            gname, gw = stepper.giver(db['start'].get(qid, []))
            ename, ew = stepper.giver(db['end'].get(qid, []))
            a = ['a', qid, {'n2': gname} if gname else {}]
            if gw:
                a[2].update(m=gw[0], x=gw[1], y=gw[2])
                entrance[gw[0]] += 1
            step = {'t': gname or db['quest'][qid]['title'], 'lv': max(lvl - 2, 1), 'g': [a]}
            if qcls:
                step['cls'] = qcls
            acc_steps.append(step)
            run_goals += stepper.objectives(qid)
            t = ['t', qid, {'n2': ename} if ename else {}]
            if ew:
                t[2].update(m=ew[0], x=ew[1], y=ew[2])
            tstep = {'t': ename or db['quest'][qid]['title'], 'lv': lvl, 'g': [t]}
            if qcls:
                tstep['cls'] = qcls
            turn_steps.append(tstep)
        bosses = collections.defaultdict(list)
        for iid, s in lev['src'].items():
            for tok in s.split():
                m = re.match(r'd(\d+)x(\d+)z(\d+)$', tok)
                if m and dungeon_of_area(int(m.group(3)), zones) == zname and int(m.group(1)) and int(m.group(2)) / 10 >= MIN_DROP_PCT:
                    bosses[int(m.group(1))].append((iid, int(m.group(2)) / 10))
        boss_ids = sorted(bosses)
        run = {'t': 'Run %s' % zname, 'lv': lvl, 'n': 'Your gear plan names the boss drops it wants; the Gear tab and "Gear here" show which.',
               'g': run_goals + [['i', 0, {'txt': 'Boss: %s' % lev['npcs'].get(b, db['npc'].get(b, b))}] for b in boss_ids]}
        dung_out[(faction, zname)] = dict(title=zname, lv=lvl, m=entrance.most_common(1)[0][0] if entrance else None,
                                         steps=merge_steps(acc_steps) + [run] + merge_steps(turn_steps),
                                         bosses={b: [i for i, _ in bosses[b]] for b in boss_ids})

    # ---------------------------------------------------------------- items
    def src_text(e):
        s = e['src']
        if s['kind'] == 'quest':
            title = db['quest'][s['quest']]['title']
            zn = s['dungeon']   # other quests: the step and its waypoint say where (givers can differ by faction)
            return 'Q: %s%s' % (title, (' (%s)' % zn) if zn else '')
        if s['kind'] == 'drop':
            return '%s, %s (%g%%)' % (lev['npcs'].get(s['npc'], db['npc'].get(s['npc'], 'boss')), s['dungeon'], s['pct'])
        return 'Craft: %s %d (or the Auction House)' % (s['prof'], s['skill'])

    lines = ['-- Generated by tools/build_bis.py. Do not edit by hand.',
             '-- Item stats and sources: Polestar Item Data (GPL-3.0), including facts derived from ForeverLevelingBiS',
             '-- %s by Thunder (MIT, data %s); stat weights: Polestar SpecData (Polestar levelling weights and wowsims, MIT).' % (meta.get('version'), meta.get('generated')),
             '-- Quests, givers, objectives and spawns: Polestar forever-db (from the Forever client). See NOTICE.md.',
             'local FP = ForeverPlanner', 'local B = FP:BiSData()', '']
    lines.append('-- item ID -> { name, where it comes from, quest = ID, drop = { npc, dungeon area }, craft = true }')
    lines.append('B:Items({')
    for iid in sorted(used_items):
        e = used_items[iid]
        s = e['src']
        rec = {1: lev['names'].get(iid) or db['item'].get(iid) or ('item %d' % iid), 2: src_text(e)}
        if s['kind'] == 'quest':
            rec['q'] = s['quest']
            if s['dungeon']:
                rec['d'] = s['dungeon']
        elif s['kind'] == 'drop':
            rec['d'] = s['dungeon']
            rec['npc'] = s['npc']
        else:
            rec['c'] = True
        lines.append('  [%d]=%s,' % (iid, lua_val(rec)))
    lines.append('})')
    lines.append('')
    for (faction, qid), ch in chain_out.items():
        head = {'faction': faction, 'lv': ch['lv'], 'title': ch['title']}
        if ch['m']:
            head['m'] = ch['m']
        lines.append('B:Chain(%d, %s, function() return {' % (qid, lua_val(head)))
        lines += write_steps(ch['steps'])
        lines.append('} end)')
    lines.append('')
    for (faction, zname), dg in dung_out.items():
        head = {'faction': faction, 'id': zname, 'title': dg['title'], 'lv': dg['lv']}
        if dg['m']:
            head['m'] = dg['m']
        lines.append('B:Dungeon(%s, function() return {' % lua_val(head))
        for st in dg['steps']:
            p = ['t=%s' % lua_str(st['t']), 'lv=%d' % st['lv']]
            if st.get('n'):
                p.append('n=%s' % lua_str(st['n']))
            if st.get('cls'):
                p.append('cls=%d' % st['cls'])
            p.append('g={%s}' % ','.join(write_goal(g) for g in st['g']))
            lines.append('  {' + ', '.join(p) + '},')
        lines.append('} end)')
    lines.append('')
    for cls, spec, faction, plan in plans:
        out = []
        for lo, hi, entries in plan:
            sl = []
            for slot, c in entries:
                rec = {1: slot, 2: c['best']['id']}
                if c.get('alt'):
                    rec[3] = c['alt']['id']
                sl.append(lua_val(rec))
            out.append('{%d,%d,{%s}}' % (lo, hi, ','.join(sl)))
        lines.append('B:Plan(%s,%s,%s,{%s})' % (lua_str(cls), lua_str(spec), lua_str(faction), ','.join(out)))
    with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')
    print('items %d, chains %d, dungeon runs %d, plans %d, %d bytes' % (len(used_items), len(chain_out), len(dung_out), len(plans), os.path.getsize(OUT)))
    for r in report:
        print('  ' + r)


if __name__ == '__main__':
    main()
