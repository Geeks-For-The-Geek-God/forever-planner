#!/usr/bin/env python3
"""Finds the item ID for every item a class file names by name (gear tables and stopgaps), so the
character-window gear panel can show icons and item tooltips. Writes `plan.itemIds` into the class file.

Usage: python tools/map_item_ids.py <polestar checkout> ForeverPlanner/Data/Classes/Druid.lua
"""
import json
import os
import re
import sys

from lupa.lua51 import LuaRuntime

BEGIN = '-- BEGIN generated item IDs (tools/map_item_ids.py)'
END = '-- END generated item IDs'


def norm(s):
    return re.sub(r'\s+', ' ', re.sub(r'[^\w\s]', '', s.lower())).strip()


def main():
    polestar, path = sys.argv[1], sys.argv[2]
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
      ForeverPlanner = {}
      local FP = ForeverPlanner
      local function mk(kind) return function(title, extra) return { k = kind, q = title } end end
      FP.A, FP.T, FP.C = mk("a"), mk("t"), mk("c")
      function FP:RegisterPlan(p) CAPTURED = p end
      function FP:RegisterClass(c) end
    ''')
    lua.execute(open(path, encoding='utf-8').read())
    plan = lua.globals().CAPTURED
    names = set()
    for g in (plan.gear or {}).values():
        for s in g.slots.values():
            for k in ('best', 'alt'):
                if s[k]:
                    names.add(s[k])
    for s in (plan.stopgaps or {}).values():
        names.add(s.name)
    ids = {}
    with open(os.path.join(polestar, 'forever-db/data/item.jsonl'), encoding='utf-8') as f:
        for line in f:
            d = json.loads(line)
            if d.get('name'):
                ids.setdefault(norm(d['name']), d['id'])
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import lualit
    fsrc = open(os.path.join(polestar, 'addon/Polestar_ItemDB/Forever.lua'), encoding='utf-8').read()
    lev = list(lualit.call_args(fsrc, 'DB.RegisterLeveling'))[0][1]
    for iid, n in lev['names'].items():
        ids.setdefault(norm(n), iid)
    found = {norm(n): ids[norm(n)] for n in names if norm(n) in ids}
    missing = sorted(n for n in names if norm(n) not in ids)
    block = '\n'.join([BEGIN, '-- Item IDs for the gear names above, from the Forever client\'s item table (Polestar forever-db).',
                       'plan.itemIds = {'] + ['  [%s] = %d,' % (json.dumps(k), v) for k, v in sorted(found.items())] + ['}', END])
    src = open(path, encoding='utf-8').read()
    if BEGIN in src:
        src = re.sub(re.escape(BEGIN) + r'.*?' + re.escape(END), lambda m: block, src, flags=re.S)
    else:
        src = src.replace('FP:RegisterPlan(plan)', block + '\n\nFP:RegisterPlan(plan)')
    open(path, 'w', encoding='utf-8', newline='\n').write(src)
    print('items %d, found %d, not found %d' % (len(names), len(found), len(missing)))
    for n in missing:
        print('  not found:', n)


if __name__ == '__main__':
    main()
