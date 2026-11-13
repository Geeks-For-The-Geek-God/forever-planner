#!/usr/bin/env python3
"""Finds the quest ID for every quest a class file names by title (the Druid's own route).

Matching by ID means a quest still ticks when the title in the plan differs slightly from the game's.
Reads the class file with the addon's own constructors (lupa) and the quest table from Polestar's
forever-db (quest.jsonl, read from the Forever client), then writes a `plan.questIds` block into the
class file between the markers below. Titles that occur more than once on the route (a chain reusing
a name) get one ID per occurrence, in chain order.

Usage: python tools/map_quest_ids.py <polestar checkout> ForeverPlanner/Data/Classes/Druid.lua [Horde|Alliance]
"""
import difflib
import json
import os
import re
import sys

from lupa.lua51 import LuaRuntime

BEGIN = '-- BEGIN generated quest IDs (tools/map_quest_ids.py)'
END = '-- END generated quest IDs'


def norm(s):
    s = s.lower()
    s = re.sub(r'[^\w\s]', '', s)
    return re.sub(r'\s+', ' ', s).strip()


def load_plan(path):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
      ForeverPlanner = {}
      local FP = ForeverPlanner
      local function mk(kind) return function(title, extra)
        local o = { k = kind, q = title }
        if extra == true then o.opt = true elseif type(extra) == "number" then o.n = extra end
        return o end end
      FP.A, FP.T, FP.C = mk("a"), mk("t"), mk("c")
      function FP:RegisterPlan(p) CAPTURED = p end
      function FP:RegisterClass(c) end
    ''')
    src = open(path, encoding='utf-8').read()
    lua.execute(src)
    plan = lua.globals().CAPTURED
    out = []
    for i in range(1, len(plan.route) + 1):
        s = plan.route[i]
        for j in range(1, len(s.q or []) + 1):
            o = s.q[j]
            out.append((s.key, o.k, o.q, o.n or 1))
    return out


def main():
    polestar, cls_file = sys.argv[1], sys.argv[2]
    side = {'Horde': 2, 'Alliance': 1}[sys.argv[3] if len(sys.argv) > 3 else 'Horde']
    quests, by_title = {}, {}
    with open(os.path.join(polestar, 'forever-db/data/quest.jsonl'), encoding='utf-8') as f:
        for line in f:
            d = json.loads(line)
            if d.get('side') not in (0, side) or not d.get('title'):
                continue
            quests[d['id']] = d
            by_title.setdefault(norm(d['title']), []).append(d['id'])
    prereq = {}
    with open(os.path.join(polestar, 'forever-db/data/quest_prereq.jsonl'), encoding='utf-8') as f:
        for line in f:
            d = json.loads(line)
            if not d.get('breadcrumb'):
                prereq.setdefault(d['quest'], set()).add(d['pre'])

    def depth(qid, seen=()):
        if qid in seen:
            return 0
        return 1 + max((depth(p, seen + (qid,)) for p in prereq.get(qid, ()) if p in quests), default=0)

    goals = load_plan(cls_file)
    wanted = {}
    for key, kind, title, n in goals:
        t = norm(title)
        wanted[t] = max(wanted.get(t, 0), n)
    ids, missing, fuzzy, short = {}, [], [], []
    titles = {norm(title): title for _, _, title, _ in goals}
    for t, n in sorted(wanted.items()):
        cands = by_title.get(t)
        if not cands:
            guess = difflib.get_close_matches(t, by_title.keys(), n=1, cutoff=0.86)
            if guess:
                cands = by_title[guess[0]]
                fuzzy.append('%s -> %s' % (titles[t], quests[cands[0]]['title']))
            else:
                missing.append(titles[t])
                continue
        cands = sorted(cands, key=lambda q: (depth(q), quests[q].get('level', 0), q))
        if len(cands) < n:
            short.append('%s (route uses %d, game has %d)' % (titles[t], n, len(cands)))
        ids[t] = cands
    lines = [BEGIN, '-- Quest IDs for the titles above, from the Forever client\'s quest table (Polestar forever-db).',
             '-- A title used for several quests lists them in chain order; the route\'s Nth use gets the Nth ID.',
             'plan.questIds = {']
    for t in sorted(ids):
        lines.append('  [%s] = { %s },' % (json.dumps(t), ', '.join(str(q) for q in ids[t])))
    lines += ['}', END]
    block = '\n'.join(lines)
    src = open(cls_file, encoding='utf-8').read()
    if BEGIN in src:
        src = re.sub(re.escape(BEGIN) + r'.*?' + re.escape(END), lambda m: block, src, flags=re.S)
    else:
        src = src.replace('FP:RegisterPlan(plan)', block + '\n\nFP:RegisterPlan(plan)')
    with open(cls_file, 'w', encoding='utf-8', newline='\n') as f:
        f.write(src)
    print('titles: %d, mapped: %d, close matches: %d, not found: %d' % (len(wanted), len(ids), len(fuzzy), len(missing)))
    for x in fuzzy:
        print('  close match:', x)
    for x in missing:
        print('  not found:', x)
    for x in short:
        print('  fewer quests than uses:', x)


if __name__ == '__main__':
    main()
