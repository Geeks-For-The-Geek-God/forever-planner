#!/usr/bin/env python3
"""Converts Polestar's compiled guides and talent builds into Forever Planner data.

Polestar (https://github.com/fitzforge/polestar, GPL-3.0-only) publishes levelling
routes for WoW: Forever. This reads its compiled guide files as data (nothing from
Polestar is executed) and writes:

  ForeverPlanner/Data/Routes/Horde.lua        levelling segments, Horde
  ForeverPlanner/Data/Routes/Alliance.lua     levelling segments, Alliance
  ForeverPlanner/Data/Routes/ClassQuests.lua  class quest side guides (pets, forms, class items)
  ForeverPlanner/Data/Talents.lua             levelling talent builds for all nine classes

Usage: python tools/convert_polestar.py /path/to/polestar
The Polestar commit used is written into each file's header and data-sources.json.
"""
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lualit  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'ForeverPlanner', 'Data')

CLASS_TOKENS = {'Warrior': 'WARRIOR', 'Paladin': 'PALADIN', 'Hunter': 'HUNTER', 'Rogue': 'ROGUE', 'Priest': 'PRIEST',
                'Shaman': 'SHAMAN', 'Mage': 'MAGE', 'Warlock': 'WARLOCK', 'Druid': 'DRUID'}

# --------------------------------------------------------------------------- text


def resolver(guide):
    names = guide.get('names') or {}
    written = guide.get('written') or {}

    def res(text):
        if text is None:
            return None
        if text in written:
            return written[text]

        def sub(m):
            return names.get('%s:%s' % (m.group(1), m.group(2)), m.group(2))
        return re.sub(r'\{(\w+):(\d+)\}', sub, text)
    return res


def lua_str(s):
    s = str(s)
    s = s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '')
    return '"' + s + '"'


def lua_val(v):
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int,)):
        return str(v)
    if isinstance(v, float):
        r = round(v, 2)
        return str(int(r)) if r == int(r) else ('%g' % r)
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, list):
        return '{' + ','.join(lua_val(x) for x in v) + '}'
    if isinstance(v, dict):
        parts = []
        for k, x in v.items():
            if x is None:
                continue
            if isinstance(k, int):
                parts.append('[%d]=%s' % (k, lua_val(x)))
            elif re.match(r'^[A-Za-z_]\w*$', k):
                parts.append('%s=%s' % (k, lua_val(x)))
            else:
                parts.append('[%s]=%s' % (lua_str(k), lua_val(x)))
        return '{' + ','.join(parts) + '}'
    raise TypeError(type(v))

# --------------------------------------------------------------------------- maps


def load_frames(polestar):
    src = open(os.path.join(polestar, 'addon/Polestar_Guides/MapFrames.lua'), encoding='utf-8').read()
    era = next(lualit.register_calls(src, 'Polestar.RegisterMapFrames'))['era']
    live = {}
    with open(os.path.join(polestar, 'forever-db/data/ui_map.jsonl'), encoding='utf-8') as f:
        for line in f:
            d = json.loads(line)
            live[d['ui_map']] = d
    return era, live


class Coords:
    def __init__(self, era, live):
        self.era, self.live = era, live
        self.changed = set()

    def to_live(self, m, x, y, frame):
        """Polestar types coordinates in the Era map frame; Forever moved some zones (Mulgore is bigger),
        so era points are turned into world points and back into the client's own map frame."""
        if frame != 'e':
            return x, y
        e, l = self.era.get(m), self.live.get(m)
        if not e or not l:
            return x, y
        same = all(abs(e[k] - l[k]) < 0.01 for k in ('left', 'right', 'top', 'bottom'))
        if same:
            return x, y
        self.changed.add(m)
        wa = e['left'] + (e['right'] - e['left']) * x / 100.0
        wb = e['top'] + (e['bottom'] - e['top']) * y / 100.0
        nx = (wa - l['left']) / (l['right'] - l['left']) * 100.0
        ny = (wb - l['top']) / (l['bottom'] - l['top']) * 100.0
        return nx, ny

# --------------------------------------------------------------------------- goals


def only_of(o):
    """Polestar 'only' ({classes=, races=, faction=}) -> compact filter."""
    if not o:
        return None
    f = {}
    if o.get('classes'):
        f['c'] = list(o['classes'])
    if o.get('races'):
        f['r'] = list(o['races'])
    if o.get('notClasses'):
        f['nc'] = list(o['notClasses'])
    if o.get('notRaces'):
        f['nr'] = list(o['notRaces'])
    if o.get('factions'):
        f['fa'] = list(o['factions'])
    for k in o:
        if k not in ('classes', 'races', 'notClasses', 'notRaces', 'factions'):
            raise ValueError('unknown only key %s' % k)
    return f or None


def convert_goal(g, res, coords, titles):
    t = g['t']
    out = {}
    qid = g.get('quest')
    if qid and g.get('title'):
        titles[qid] = g['title']
    kind, ident, text = None, 0, None
    if t == 'accept':
        kind, ident = 'a', qid
    elif t == 'turnin':
        kind, ident = 't', qid
    elif t == 'complete':
        kind, ident = 'c', qid
        objs = g.get('objs') or []
        if objs:
            text = '; '.join(res(o.get('text') or '') for o in objs if o.get('text'))
    elif t in ('kill', 'collect', 'use', 'interact', 'talk') and qid and g.get('oi'):
        kind, ident = 'o', qid
        out['i'] = g['oi']
        cnt = g.get('count')
        if t == 'kill':
            text = 'Kill %s' % (res(g.get('target')) or 'targets')
        elif t == 'collect':
            text = res(g.get('itemName')) or 'items'
        elif t == 'use':
            text = 'Use %s' % (res(g.get('itemName')) or 'the item')
        elif t == 'interact':
            text = res(g.get('objName')) or 'Click the object'
        elif t == 'talk':
            text = 'Talk to %s' % (res(g.get('npcName')) or 'the NPC')
        if g.get('text'):
            text = res(g['text'])
        if cnt and cnt > 1:
            text = '%s x%d' % (text, cnt)
    elif t == 'level':
        kind, ident = 'l', g['level']
        if g.get('frac'):
            out['fr'] = g['frac']
        text = 'Reach level %s%s' % (g['level'], (' (%d%% in)' % round(g['frac'] * 100)) if g.get('frac') else '')
        if g.get('npcName'):
            text += ': grind %s' % res(g['npcName'])
    elif t == 'goto':
        kind = 'g'
        text = res(g.get('text')) or 'Go here'
    elif t == 'train':
        kind = 'tr'
        if g.get('skill'):
            text = 'Learn %s%s' % (g['skill'], (' from %s' % g['npcName']) if g.get('npcName') else '')
        elif g.get('class'):
            text = 'Visit your class trainer'
        else:
            text = 'Train with %s' % (g.get('npcName') or 'the trainer')
    elif t in ('fly', 'die', 'enter'):
        kind = 'z'
        loc = res(g.get('location')) or ''
        text = {'fly': 'Fly to %s', 'die': 'Die and resurrect at %s', 'enter': 'Go to %s'}[t] % loc
        out['at'] = loc
    elif t == 'getfp':
        kind, ident = 'fp', g.get('node') or 0
        text = 'Get the %s flight path%s' % (res(g.get('location')), (' (%s)' % g['npcName']) if g.get('npcName') else '')
    elif t == 'sethome':
        kind = 'b'
        text = 'Set your hearthstone at %s' % res(g.get('location'))
        out['at'] = res(g.get('location'))
    elif t == 'talk':
        kind, ident = 'tk', g.get('npc') or 0
        text = 'Talk to %s' % res(g.get('npcName'))
    elif t in ('collect', 'buy'):
        kind, ident = 'h', g.get('item')
        cnt = g.get('count') or 1
        out['n'] = cnt
        verb = 'Buy' if t == 'buy' else 'Get'
        text = '%s %s%s' % (verb, res(g.get('itemName')), (' x%d' % cnt) if cnt > 1 else '')
        if t == 'buy' and g.get('npcName'):
            text += ' (%s)' % res(g['npcName'])
    else:  # kill/use/interact without a quest, note, vendor
        kind = 'i'
        if t == 'note':
            text = res(g.get('text'))
        elif t == 'vendor':
            text = 'Sell and repair%s' % ((' at %s' % res(g['npcName'])) if g.get('npcName') else '')
        elif t == 'kill':
            text = 'Kill %s%s' % (res(g.get('target')), (' x%d' % g['count']) if (g.get('count') or 1) > 1 else '')
        elif t == 'use':
            text = 'Use %s' % res(g.get('itemName'))
        elif t == 'interact':
            text = res(g.get('objName'))
        else:
            text = res(g.get('text')) or t
    out_list = [kind, ident if ident is not None else 0]
    if text:
        out['txt'] = text
    if g.get('note'):
        out['n2'] = res(g['note'])
    if 'map' in g and 'x' in g:
        x, y = coords.to_live(g['map'], g['x'], g['y'], g.get('f'))
        out['m'], out['x'], out['y'] = g['map'], round(x, 1), round(y, 1)
    if g.get('optional') or (t == 'vendor'):
        out['opt'] = True
    if g.get('group'):
        out['grp'] = True
    f = only_of(g.get('only'))
    if f:
        out['f'] = f
    if t == 'accept' and g.get('minLevel'):
        out['ml'] = g['minLevel']
    return out_list, out


def step_level(goals, prev):
    lv = prev
    for g in goals:
        if g['t'] == 'level':
            lv = max(lv, g['level'])
        elif g['t'] == 'accept' and g.get('minLevel'):
            lv = max(lv, g['minLevel'])
    return lv


def convert_guide(gd, coords):
    res = resolver(gd)
    titles = {}
    steps = []
    lv = gd['minLevel']
    for s in gd['steps']:
        goals = s.get('goals') or []
        lv = min(max(step_level(goals, lv), gd['minLevel']), gd['maxLevel'])
        st = {'t': res(s.get('title')) or '', 'lv': lv}
        if s.get('note'):
            st['n'] = res(s['note'])
        if s.get('when'):
            st['w'] = s['when']
        f = only_of(s.get('only'))
        if f:
            st['f'] = f
        if s.get('along'):
            a = s['along']
            st['al'] = (a[1] if isinstance(a, list) and len(a) > 1 and a[1] else True)
        if s.get('label'):
            st['lb'] = s['label']
        st['g'] = [convert_goal(g, res, coords, titles) for g in goals]
        steps.append(st)
    seg = {
        'id': gd['id'].replace('forever/', '', 1),
        'title': res(gd['title']),
        'faction': gd.get('faction'),
        'races': gd.get('races'),
        'classes': gd.get('classes'),
        'min': gd['minLevel'], 'max': gd['maxLevel'],
        'zone': gd.get('zone'), 'zoneName': gd.get('zoneName'),
        'next': gd['next'].replace('forever/', '', 1) if gd.get('next') else None,
    }
    if gd.get('category') == 'Class':
        seg['why'] = res(gd.get('why'))
        seg['folder'] = gd.get('folder')
    zones = {}
    for k, v in (gd.get('names') or {}).items():
        if k.startswith('zone:'):
            zones[int(k[5:])] = v
    return seg, steps, titles, zones


def write_goal(kind_ident, extra):
    kind, ident = kind_ident
    parts = [lua_str(kind), lua_val(ident)]
    for k in ('i', 'txt', 'n2', 'm', 'x', 'y', 'n', 'fr', 'at', 'opt', 'grp', 'f', 'ml'):
        if k in extra:
            parts.append('%s=%s' % (k, lua_val(extra[k])))
    return '{' + ','.join(parts) + '}'


def write_file(path, header, segments, titles, zones):
    lines = [header, 'local FP = ForeverPlanner', 'local R = FP:RouteData()', '']
    lines.append('-- Quest titles by ID (used for display and as a fallback when the client has no title).')
    lines.append('R:Titles({')
    for qid in sorted(titles):
        lines.append('  [%d]=%s,' % (qid, lua_str(titles[qid])))
    lines.append('})')
    lines.append('R:Zones(%s)' % lua_val({k: zones[k] for k in sorted(zones)}))
    lines.append('')
    for seg, steps in segments:
        head = {k: v for k, v in seg.items() if v is not None}
        lines.append('R:Segment(%s, function() return {' % lua_val(head))
        for st in steps:
            p = ['t=%s' % lua_str(st['t']), 'lv=%d' % st['lv']]
            for k in ('n', 'w', 'f', 'al', 'lb'):
                if k in st:
                    p.append('%s=%s' % (k, lua_val(st[k])))
            gl = ','.join(write_goal(*g) for g in st['g'])
            p.append('g={%s}' % gl)
            lines.append('  {' + ', '.join(p) + '},')
        lines.append('} end)')
        lines.append('')
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines))
    return os.path.getsize(path)

# --------------------------------------------------------------------------- talents


def convert_talents(polestar, header):
    lines = [header, 'local FP = ForeverPlanner', '']
    for fn in sorted(os.listdir(os.path.join(polestar, 'talents/forever'))):
        d = json.load(open(os.path.join(polestar, 'talents/forever', fn), encoding='utf-8'))
        builds = []
        for b in d['builds']:
            picks, notes = {}, {}
            for p in b['picks']:
                picks[p['level']] = '%s %d' % (p['talent'], p['rank'])
                if p.get('note'):
                    notes[p['level']] = p['note']
            builds.append({'key': b['key'], 'spec': b['spec'], 'split': b['split'], 'link': b.get('link'),
                           'talents': picks, 'notes': notes})
        reg = {'class': d['class'], 'summary': d.get('summary'), 'order': d.get('order'),
               'source': d.get('source'), 'sourceUrl': d.get('sourceUrl'), 'checkedOn': d.get('checkedOn'),
               'builds': builds}
        lines.append('FP:RegisterTalentBuilds(%s)' % lua_val(reg))
        lines.append('')
    path = os.path.join(OUT, 'Talents.lua')
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines))
    return os.path.getsize(path)

# --------------------------------------------------------------------------- main


def main():
    polestar = sys.argv[1] if len(sys.argv) > 1 else '/home/claude/fitzforge/polestar'
    try:
        commit = subprocess.check_output(['git', '-C', polestar, 'rev-parse', 'HEAD'], text=True).strip()
    except Exception:
        commit = 'unknown'
    pack = open(os.path.join(polestar, 'addon/Polestar_Guides/Pack.lua'), encoding='utf-8').read()
    version = re.search(r'version = "([^"]+)"', pack).group(1)
    header = ('-- Generated by tools/convert_polestar.py from Polestar %s (commit %s). Do not edit by hand.\n'
              '-- Route data: Polestar (https://github.com/fitzforge/polestar), GPL-3.0-only. See NOTICE.md.' % (version, commit[:12]))
    era, live = load_frames(polestar)
    coords = Coords(era, live)
    os.makedirs(os.path.join(OUT, 'Routes'), exist_ok=True)

    lev = {'Horde': [], 'Alliance': []}
    cls = []
    titles = {'Horde': {}, 'Alliance': {}, 'Class': {}}
    zones = {'Horde': {}, 'Alliance': {}, 'Class': {}}
    srcs = ['Polestar_Guides_Horde/Guides.lua', 'Polestar_Guides_Alliance/Guides.lua', 'Polestar_Guides/Guides.lua']
    for rel in srcs:
        src = open(os.path.join(polestar, 'addon', rel), encoding='utf-8').read()
        for gd in lualit.register_calls(src):
            cat = gd.get('category')
            if cat == 'Leveling':
                seg, steps, t, z = convert_guide(gd, coords)
                fac = seg['faction']
                lev[fac].append((seg, steps))
                titles[fac].update(t)
                zones[fac].update(z)
            elif cat == 'Class':
                seg, steps, t, z = convert_guide(gd, coords)
                cls.append((seg, steps))
                titles['Class'].update(t)
                zones['Class'].update(z)
    sizes = {}
    for fac in ('Horde', 'Alliance'):
        lev[fac].sort(key=lambda p: p[0]['id'])
        sizes[fac] = write_file(os.path.join(OUT, 'Routes', fac + '.lua'), header, lev[fac], titles[fac], zones[fac])
    cls.sort(key=lambda p: p[0]['id'])
    sizes['ClassQuests'] = write_file(os.path.join(OUT, 'Routes', 'ClassQuests.lua'), header, cls, titles['Class'], zones['Class'])
    sizes['Talents'] = convert_talents(polestar, header.replace('Route data', 'Talent builds (from ForeverDB via Polestar)'))

    ds_path = os.path.join(ROOT, 'data-sources.json')
    ds = json.load(open(ds_path, encoding='utf-8'))
    ds['Polestar'] = {
        'repo': 'https://github.com/fitzforge/polestar', 'license': 'GPL-3.0-only', 'version': version, 'commit': commit,
        'files': ['ForeverPlanner/Data/Routes/Horde.lua', 'ForeverPlanner/Data/Routes/Alliance.lua',
                  'ForeverPlanner/Data/Routes/ClassQuests.lua', 'ForeverPlanner/Data/Talents.lua'],
        'regenerate': 'python tools/convert_polestar.py <path to a polestar checkout>',
    }
    with open(ds_path, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(ds, f, indent=2)
        f.write('\n')
    print('Polestar %s %s' % (version, commit[:12]))
    for fac in ('Horde', 'Alliance'):
        print('%s: %d segments, %d steps' % (fac, len(lev[fac]), sum(len(s) for _, s in lev[fac])))
    print('Class quests: %d guides' % len(cls))
    print('Era->live coordinate fixes on maps:', sorted(coords.changed))
    print('Sizes:', sizes)


if __name__ == '__main__':
    main()
