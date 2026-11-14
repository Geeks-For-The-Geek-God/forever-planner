-- Forever Planner: Priest class file.
-- From the project's Priest brief (claude/classes/priest.md, 10 Nov 2026): Discipline wand levelling 10-39
-- (23/0/7, Maxroll 4 Nov 2026), respec into Shadow at 40 (17/0/34), and the five-key macro set.
-- Talent names checked against Forever's live trees (timesaver.gg calculator, read 14 Nov 2026).
-- Trainer levels: conquestcapped.com "WoW Forever Priest Abilities and Spells by Level" (7 Nov 2026).
-- Gear: the best-in-slot gear route (Data/Routes/BiS.lua) for Discipline to 39 and Shadow from 40.
-- Format: claude/addon/README.md in the project, "Class files".
local FP = ForeverPlanner
local function M(name, from, to, bar, desc, text) return { name = name, from = from, to = to, bar = bar, desc = desc, text = text } end

------------------------------------------------------------------------
-- TALENTS
------------------------------------------------------------------------
local DISC_WAND = {   -- levels 10-39: Discipline wand, 23/0/7
  [10]="Wand Specialization 1", [11]="Wand Specialization 2",
  [12]="Spirit Tap 1", [13]="Spirit Tap 2", [14]="Spirit Tap 3", [15]="Spirit Tap 4", [16]="Spirit Tap 5",
  [17]="Twin Disciplines 1", [18]="Twin Disciplines 2", [19]="Twin Disciplines 3",
  [20]="Holy Precision 1", [21]="Twin Disciplines 4", [22]="Twin Disciplines 5",
  [23]="Mental Strength 1", [24]="Mental Strength 2", [25]="Inner Focus",
  [26]="Meditation 1", [27]="Meditation 2", [28]="Meditation 3",
  [29]="Mental Agility 1", [30]="Mental Agility 2", [31]="Mental Agility 3",
  [32]="Improved Power Word: Shield 1", [33]="Improved Power Word: Shield 2", [34]="Improved Power Word: Shield 3",
  [35]="Penance", [36]="Improved Shadow Word: Pain 1", [37]="Improved Shadow Word: Pain 2",
  [38]="Soul Warding", [39]="Renewed Hope 1",
}
local DISC_NOTES = {
  [10]="Wand Specialization: +25% wand damage. The wand does most of your damage for no mana.",
  [12]="Spirit Tap (Shadow tree): big regen after each kill, so you rarely drink.",
  [17]="Twin Disciplines: +5% to your instant damage and heals.",
  [26]="Meditation: mana regen keeps going while you cast.",
  [32]="Improved Power Word: Shield: a bigger shield, so fewer pushbacks and less healing.",
  [35]="Penance joins the ATTACK sequence after Mind Blast (ATTACK 35-39 macro).",
}

local SHADOW = {   -- 17/0/34: the 31 Shadow points first (all at once after the respec at 40), then Discipline
  [10]="Shadow Focus 1", [11]="Shadow Focus 2", [12]="Shadow Focus 3",
  [13]="Spirit Tap 1", [14]="Spirit Tap 2", [15]="Spirit Tap 3", [16]="Spirit Tap 4", [17]="Spirit Tap 5",
  [18]="Improved Shadow Word: Pain 1", [19]="Improved Shadow Word: Pain 2", [20]="Mind Flay",
  [21]="Improved Mind Flay 1", [22]="Improved Mind Flay 2", [23]="Shadow Reach 1", [24]="Shadow Reach 2",
  [25]="Vampiric Embrace", [26]="Shadow Weaving 1", [27]="Shadow Weaving 2", [28]="Shadow Weaving 3",
  [29]="Dark Inspiration 1", [30]="Dark Inspiration 2", [31]="Dark Inspiration 3",
  [32]="Devouring Contagion 1", [33]="Devouring Contagion 2", [34]="Silence",
  [35]="Darkness 1", [36]="Darkness 2", [37]="Darkness 3", [38]="Darkness 4", [39]="Darkness 5", [40]="Shadowform",
  [41]="Wand Specialization 1", [42]="Wand Specialization 2",
  [43]="Twin Disciplines 1", [44]="Twin Disciplines 2", [45]="Twin Disciplines 3", [46]="Twin Disciplines 4", [47]="Twin Disciplines 5",
  [48]="Mental Strength 1", [49]="Mental Strength 2", [50]="Mental Strength 3", [51]="Inner Focus",
  [52]="Meditation 1", [53]="Meditation 2", [54]="Meditation 3",
  [55]="Mental Agility 1", [56]="Mental Agility 2", [57]="Mental Agility 3",
  [58]="Dark Inspiration 4", [59]="Dark Inspiration 5", [60]="Shadow Focus 4",
}
local SHADOW_NOTES = {
  [10]="Shadow Focus: 1% Shadow hit per rank.",
  [20]="Mind Flay: your filler and slow; the ATTACK macro loops it between Mind Blasts.",
  [40]="Shadowform: +10% Shadow damage, half-cost Shadow spells, double Shadow crit bonus, 15% less physical damage taken. No healing spells in form (DEFEND's Shift heal drops it).",
  [41]="The last 20 points go back into Discipline: wand, Twin Disciplines, Mental Strength, Inner Focus, Meditation, Mental Agility.",
}

------------------------------------------------------------------------
-- TRAINER (new spells by level; Q = from a class quest)
------------------------------------------------------------------------
local TRAINING = {
  [4] = "Shadow Word: Pain",
  [6] = "Power Word: Shield",
  [8] = "Renew, Fade",
  [10] = "Mind Blast, Resurrection, Hex of Weakness, Starshards; class quests: Touch of Weakness, Desperate Prayer, Confounding Flash, Divine Grace",
  [12] = "Inner Fire",
  [14] = "Psychic Scream, Cure Disease",
  [16] = "Heal (change DEFEND's Lesser Heal to Heal: the 16+ DEFEND macro does it)",
  [18] = "Dispel Magic",
  [20] = "Flash Heal, Holy Fire, Fear Ward, Devouring Plague, Mind Soothe, Shackle Undead, Contingency Plan; class quests: Dark Sacrifice, Shadowguard, Feedback, Elune's Grace, Chastise",
  [22] = "Mind Vision",
  [24] = "Mana Burn",
  [30] = "Divine Spirit, Prayer of Healing, Mind Control, Shadow Protection",
  [32] = "Shadow Word: Death (Ctrl on ATTACK from 40), Abolish Disease",
  [34] = "Levitate",
  [40] = "Respec to Shadow (Talents tab); Greater Heal, Lightwell; riding",
  [48] = "Prayer of Fortitude",
  [56] = "Prayer of Shadow Protection",
  [60] = "Prayer of Spirit",
}

------------------------------------------------------------------------
-- MACROS (from the brief; each <= 255 characters, checked by the tests)
------------------------------------------------------------------------
local ATTACK_WAND = M("ATTACK", 10, 34, "key 1",
  "Shadow Word: Pain, Mind Blast, then the wand; Shift = wand only. 3 taps a mob; tap again on long fights.",
  "#showtooltip\n/targetenemy [help][dead]\n/castsequence [nomod,harm,nodead] reset=target Shadow Word: Pain, Mind Blast, Shoot\n/cast [harm,nodead] !Shoot")
local ATTACK_PENANCE = M("ATTACK", 35, 39, "key 1",
  "Same, with Penance after Mind Blast (falls back to the wand if Penance is on cooldown).",
  "#showtooltip\n/targetenemy [help][dead]\n/castsequence [nomod,harm,nodead] reset=target Shadow Word: Pain, Mind Blast, Penance, Shoot\n/cast [harm,nodead] !Shoot")
local function ATTACK_SHADOW(from)
  return M("ATTACK", from, 60, "key 1",
    "Shadow rotation: SW:P, Mind Blast, Mind Flay x3, Mind Blast, Mind Flay x2, looping; Mind Flay fills. Ctrl = Shadow Word: Death as an execute only (30% max-health backlash if it doesn't kill).",
    "#showtooltip\n/cast [mod:ctrl,harm] Shadow Word: Death\n/castsequence [nomod,harm,nochanneling] reset=target Shadow Word: Pain, Mind Blast, Mind Flay, Mind Flay, Mind Flay, Mind Blast, Mind Flay, Mind Flay\n/cast [nomod,harm,nochanneling] Mind Flay")
end
local SHARED = {
  M("DEFEND", 1, 15, "key 2",
    "Power Word: Shield (mouseover > friendly target > you); Shift = Lesser Heal (drops Shadowform).",
    "#showtooltip\n/cancelaura [mod:shift] Shadowform\n/cast [mod:shift,@mouseover,help,nodead][mod:shift,help,nodead][mod:shift,@player] Lesser Heal; [@mouseover,help,nodead][help,nodead][@player] Power Word: Shield"),
  M("DEFEND", 16, 60, "key 2",
    "Same with Heal on Shift.",
    "#showtooltip\n/cancelaura [mod:shift] Shadowform\n/cast [mod:shift,@mouseover,help,nodead][mod:shift,help,nodead][mod:shift,@player] Heal; [@mouseover,help,nodead][help,nodead][@player] Power Word: Shield"),
  M("BUFF", 1, 11, "key 3",
    "Your buffs, one per press (Fortitude, Touch of Weakness); Shift = Fortitude on your mouseover or friendly target.",
    "#showtooltip\n/castsequence [nomod,@player] reset=30 Power Word: Fortitude, Touch of Weakness\n/cast [mod:shift,@mouseover,help,nodead][mod:shift,help,nodead] Power Word: Fortitude"),
  M("BUFF", 12, 60, "key 3",
    "Adds Inner Fire; Ctrl = Shadowform (from 40); Shift = Fortitude on mouseover or friend.",
    "#showtooltip\n/cast [mod:ctrl] Shadowform\n/castsequence [nomod,@player] reset=30 Power Word: Fortitude, Inner Fire, Touch of Weakness\n/cast [mod:shift,@mouseover,help,nodead][mod:shift,help,nodead] Power Word: Fortitude"),
  M("RECOVER", 1, 60, "key 4",
    "Cannibalize out of combat (Undead); Shift = drink; Ctrl = Dark Sacrifice (20, class quest).",
    "#showtooltip\n/cast [mod:ctrl] Dark Sacrifice; [nomod,nocombat] Cannibalize\n/use [mod:shift] Refreshing Spring Water"),
  M("PANIC", 14, 60, "key 5",
    "Psychic Scream; Shift = Fade; Ctrl = Will of the Forsaken (Undead).",
    "#showtooltip\n/cast [mod:ctrl] Will of the Forsaken; [mod:shift] Fade; Psychic Scream"),
}
local function Macros(first)
  local out = {}
  for _, m in ipairs(first) do out[#out + 1] = m end
  for _, m in ipairs(SHARED) do out[#out + 1] = m end
  return out
end
local MACRO_NOTE = "Keys: 1 ATTACK, 2 DEFEND, 3 BUFF, 4 RECOVER, 5 PANIC. Thumb = Shift, pinky = Ctrl, spare key = Target Nearest Enemy. "
  .. "Clear the game's own Shift+1-5 and Ctrl+1-5 bindings first. RECOVER and PANIC use Undead racials. "
  .. "If friendly casts go to the wrong target, turn off Enable Interact Key (Options)."

------------------------------------------------------------------------
-- GEAR: wands worth wearing until the plan's pick (the brief's wand path)
------------------------------------------------------------------------
local STOPGAPS = {
  { slot = "Wand", name = "Lesser Magic Wand", src = "Enchanting or the Auction House (level 5)" },
  { slot = "Wand", name = "Greater Magic Wand", src = "Enchanting or the Auction House (level 13)" },
  { slot = "Wand", name = "Sizzle Stick", src = "Q: Wailing Caverns (level 15)" },
  { slot = "Wand", name = "Charred Wand", src = "Level 19" },
  { slot = "Wand", name = "Gravestone Scepter", src = "Q: Blackfathom Deeps" },
  { slot = "Wand", name = "Dancing Flame", src = "Level 26" },
  { slot = "Wand", name = "Wand of Eventide", src = "Auction House, BoE (level 27)" },
  { slot = "Wand", name = "Wand of Mana Concentration", src = "City of Dalaran (level 27)" },
}

FP:RegisterClass({
  class = "PRIEST",
  recommended = "discipline",
  specs = {
    discipline = {
      name = "Discipline wand to 39, Shadow from 40",
      desc = "Your Priest brief: wand, Spirit Tap and a big shield to 39 (fewest buttons), then respec into Shadow at 40.",
      talentPhases = {
        { from = 10, talents = DISC_WAND, notes = DISC_NOTES, title = "Levels 10-39: Discipline wand 23/0/7",
          note = "Levels 10-39: Discipline wand 23/0/7 (Maxroll, 4 Nov 2026). At 40 you respec into Shadow 17/0/34." },
        { from = 40, respec = true, talents = SHADOW, notes = SHADOW_NOTES, title = "From 40: respec into Shadow 17/0/34",
          note = "From 40: Shadow 17/0/34. Respec at your trainer and put all 31 points into Shadow for Shadowform, then Discipline." },
      },
      gearSpecs = { { from = 40, spec = "shadow" } },
      macros = Macros({ ATTACK_WAND, ATTACK_PENANCE, ATTACK_SHADOW(40) }),
      macroNote = MACRO_NOTE, training = TRAINING, stopgaps = STOPGAPS,
    },
    shadow = {
      name = "Shadow from 10 (17/0/34)",
      desc = "Straight Shadow, no respec at 40. Weaker than the wand build until about 28.",
      talents = SHADOW, talentNotes = SHADOW_NOTES,
      talentNote = "Shadow 17/0/34 from level 10 (Maxroll, 4 Nov 2026).",
      macros = Macros({ M(ATTACK_WAND.name, 10, 19, ATTACK_WAND.bar, ATTACK_WAND.desc, ATTACK_WAND.text), ATTACK_SHADOW(20) }),
      macroNote = MACRO_NOTE, training = TRAINING, stopgaps = STOPGAPS,
    },
  },
})
