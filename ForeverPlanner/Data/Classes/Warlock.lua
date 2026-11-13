-- Forever Planner: Warlock class file (built in the WoW Forever project's Warlock chat, 13 Nov 2026).
-- Route: the shared levelling route for your race (Data/Routes). Talents: the ForeverDB builds in
-- Data/Talents.lua (client 1.60.1, checked 11 Nov 2026). This file adds macros, trainer notes and gear.
--
-- Keys (Nostromo, five keys): 1 ATTACK, 2 DOTS, 3 DRAIN, 4 PET, 5 SELF.
-- Thumb = Shift, pinky = Ctrl. Clear any Shift+1-5 / Ctrl+1-5 key bindings, or they override the macros.
-- Every macro is 255 characters or fewer and only uses Forever's supported commands and conditionals.
-- Sources: method.gg Warlock levelling guide (8 Nov 2026), Warcraft Tavern Warlock levelling guide
-- (read 13 Nov 2026), rankedboost Forever Affliction macros (10 Nov 2026). Unverified items are marked (?) .

local FP = ForeverPlanner

local function M(name, from, to, bar, desc, text)
  return { name = name, from = from, to = to, bar = bar, desc = desc, text = text }
end

-- Shared by every spec -------------------------------------------------------
local ATTACK = {
  M("ATTACK", 1, 7, "key 1",
    "Shadow Bolt; sends your pet in. Shift: wand (press again to stop).",
    "#showtooltip\n/petattack [harm,nodead]\n/cast [mod:shift] Shoot; Shadow Bolt"),
  M("ATTACK", 8, 60, "key 1",
    "Shadow Bolt; sends your pet in. Shift: wand (press again to stop). Ctrl: Fear.",
    "#showtooltip\n/petattack [harm,nodead]\n/cast [mod:ctrl] Fear; [mod:shift] Shoot; Shadow Bolt"),
}

local PET = {
  M("PET", 1, 9, "key 4", "Summon Imp.",
    "#showtooltip\n/cast Summon Imp"),
  M("PET", 10, 11, "key 4", "Shift: Summon Voidwalker. Ctrl: Summon Imp.",
    "#showtooltip\n/cast [mod:ctrl] Summon Imp; [mod:shift] Summon Voidwalker"),
  M("PET", 12, 19, "key 4", "Health Funnel on your pet. Shift: Summon Voidwalker. Ctrl: Summon Imp.",
    "#showtooltip\n/cast [mod:ctrl] Summon Imp; [mod:shift] Summon Voidwalker; Health Funnel"),
  M("PET", 20, 60, "key 4", "Health Funnel on your pet. Shift: Summon Voidwalker. Ctrl: Summon Succubus.",
    "#showtooltip\n/cast [mod:ctrl] Summon Succubus; [mod:shift] Summon Voidwalker; Health Funnel"),
}

local SELF = {
  M("SELF", 1, 9, "key 5", "Demon Skin.",
    "#showtooltip\n/cast Demon Skin"),
  M("SELF", 10, 19, "key 5", "Demon Skin. Shift: eat your healthstone.",
    "#showtooltip\n/use [mod:shift] Minor Healthstone\n/cast [nomod] Demon Skin"),
  M("SELF", 20, 21, "key 5", "Demon Armor. Shift: eat your healthstone.",
    "#showtooltip\n/use [mod:shift] Minor Healthstone\n/cast [nomod] Demon Armor"),
  M("SELF", 22, 33, "key 5", "Demon Armor. Shift: eat your healthstone (?).",
    "#showtooltip\n/use [mod:shift] Lesser Healthstone\n/cast [nomod] Demon Armor"),
  M("SELF", 34, 41, "key 5", "Demon Armor. Shift: eat your healthstone (?).",
    "#showtooltip\n/use [mod:shift] Healthstone\n/cast [nomod] Demon Armor"),
  M("SELF", 42, 45, "key 5", "Demon Armor. Shift: eat your healthstone (?). Ctrl: Death Coil.",
    "#showtooltip\n/use [mod:shift] Healthstone\n/cast [mod:ctrl] Death Coil; [nomod] Demon Armor"),
  M("SELF", 46, 57, "key 5", "Demon Armor. Shift: eat your healthstone (?). Ctrl: Death Coil.",
    "#showtooltip\n/use [mod:shift] Greater Healthstone\n/cast [mod:ctrl] Death Coil; [nomod] Demon Armor"),
  M("SELF", 58, 60, "key 5", "Demon Armor. Shift: eat your healthstone (?). Ctrl: Death Coil.",
    "#showtooltip\n/use [mod:shift] Major Healthstone\n/cast [mod:ctrl] Death Coil; [nomod] Demon Armor"),
}

-- DOTS and DRAIN for Demonology (and the base for the others) ----------------
local DOTS_BASE = {
  M("DOTS", 1, 3, "key 2", "Immolate.",
    "#showtooltip\n/cast Immolate"),
  M("DOTS", 4, 7, "key 2", "Immolate, then Corruption, on one target (new target starts again). Shift: Curse of Weakness.",
    "#showtooltip\n/cast [mod:shift] Curse of Weakness\n/castsequence [nomod] reset=target Immolate, Corruption"),
  M("DOTS", 8, 60, "key 2", "Immolate, Bane of Agony, Corruption, one per press (new target starts again). Shift: Curse of Weakness.",
    "#showtooltip\n/cast [mod:shift] Curse of Weakness\n/castsequence [nomod] reset=target Immolate, Bane of Agony, Corruption"),
}

local DRAIN_BASE = {
  M("DRAIN", 6, 9, "key 3", "Life Tap.",
    "#showtooltip\n/cast Life Tap"),
  M("DRAIN", 10, 13, "key 3", "Life Tap. Ctrl: Drain Soul (finish a mob with it for a Soul Shard).",
    "#showtooltip\n/cast [mod:ctrl,nochanneling] Drain Soul; [nomod] Life Tap"),
  M("DRAIN", 14, 60, "key 3", "Drain Life (safe to mash: does nothing while you channel). Shift: Life Tap. Ctrl: Drain Soul.",
    "#showtooltip\n/cast [mod:ctrl,nochanneling] Drain Soul; [mod:shift] Life Tap; [nochanneling] Drain Life"),
}

local function Concat(...)
  local out = {}
  for _, list in ipairs({ ... }) do for _, m in ipairs(list) do out[#out + 1] = m end end
  return out
end

-- Affliction: Corruption first (instant once Improved Corruption has 5 points at 14), no Immolate from 30.
local DOTS_AFF = {
  DOTS_BASE[1], DOTS_BASE[2],
  M("DOTS", 8, 29, "key 2", "Corruption, Bane of Agony, Immolate, one per press (new target starts again). Shift: Curse of Weakness.",
    "#showtooltip\n/cast [mod:shift] Curse of Weakness\n/castsequence [nomod] reset=target Corruption, Bane of Agony, Immolate"),
  M("DOTS", 30, 39, "key 2", "Corruption, Bane of Agony, Siphon Life (talent at 30). Shift: Curse of Weakness. Ctrl: Immolate.",
    "#showtooltip\n/cast [mod:shift] Curse of Weakness; [mod:ctrl] Immolate\n/castsequence [nomod] reset=target Corruption, Bane of Agony, Siphon Life"),
  M("DOTS", 40, 60, "key 2", "Corruption, Bane of Agony, Siphon Life. Shift: Curse of Weakness. Ctrl: Drain Soul (Wrack took its place on DRAIN).",
    "#showtooltip\n/cast [mod:shift] Curse of Weakness; [mod:ctrl,nochanneling] Drain Soul\n/castsequence [nomod] reset=target Corruption, Bane of Agony, Siphon Life"),
}
local DRAIN_AFF = {
  DRAIN_BASE[1], DRAIN_BASE[2],
  M("DRAIN", 14, 39, "key 3", DRAIN_BASE[3].desc, DRAIN_BASE[3].text),
  M("DRAIN", 40, 60, "key 3", "Wrack (talent at 40), safe to mash. Shift: Life Tap. Ctrl: Drain Life.",
    "#showtooltip\n/cast [mod:ctrl,nochanneling] Drain Life; [mod:shift] Life Tap; [nochanneling] Wrack"),
}

-- Destruction: Conflagrate (26) on DOTS Ctrl, Shadowburn (20) replaces Drain Soul, Incinerate (41) replaces Shadow Bolt.
local DOTS_DESTRO = {
  DOTS_BASE[1], DOTS_BASE[2],
  M("DOTS", 8, 25, "key 2", DOTS_BASE[3].desc, DOTS_BASE[3].text),
  M("DOTS", 26, 60, "key 2", "Immolate, Bane of Agony, Corruption, one per press. Shift: Curse of Weakness. Ctrl: Conflagrate (eats your Immolate for burst).",
    "#showtooltip\n/cast [mod:shift] Curse of Weakness; [mod:ctrl] Conflagrate\n/castsequence [nomod] reset=target Immolate, Bane of Agony, Corruption"),
}
local DRAIN_DESTRO = {
  DRAIN_BASE[1], DRAIN_BASE[2],
  M("DRAIN", 14, 19, "key 3", DRAIN_BASE[3].desc, DRAIN_BASE[3].text),
  M("DRAIN", 20, 60, "key 3", "Drain Life (safe to mash). Shift: Life Tap. Ctrl: Shadowburn (talent at 20; gives a Soul Shard if the mob dies soon after).",
    "#showtooltip\n/cast [mod:ctrl] Shadowburn; [mod:shift] Life Tap; [nochanneling] Drain Life"),
}
local ATTACK_DESTRO = {
  ATTACK[1],
  M("ATTACK", 8, 40, "key 1", ATTACK[2].desc, ATTACK[2].text),
  M("ATTACK", 41, 60, "key 1", "Incinerate (talent at 41; best on an Immolated target); sends your pet in. Shift: wand. Ctrl: Fear.",
    "#showtooltip\n/petattack [harm,nodead]\n/cast [mod:ctrl] Fear; [mod:shift] Shoot; Incinerate"),
}

-- Trainer: new spells by level (Warcraft Tavern milestones and method.gg, Nov 2026) --------------
local TRAINING = {
  [1] = "Shadow Bolt, Immolate, Demon Skin; Summon Imp (class quest)",
  [4] = "Corruption, Curse of Weakness; Blood Pact for the Imp (demon trainer)",
  [6] = "Life Tap, Shadow Bolt rank 2",
  [8] = "Bane of Agony, Fear",
  [10] = "Drain Soul, Create Healthstone; Summon Voidwalker (class quest: Gan'rul's Summons, on your route)",
  [12] = "Health Funnel",
  [14] = "Drain Life, Curse of Recklessness (never on a mob you'll Fear)",
  [18] = "Searing Pain, Create Soulstone",
  [20] = "Demon Armor, Curse of the Elements, Rain of Fire, Ritual of Summoning; Succubus/Incubus class quest",
  [26] = "Curse of Tongues",
  [28] = "Banish, Create Firestone",
  [30] = "Hellfire, Subjugate Demon; Felhunter class quest (/fp side)",
  [32] = "Shadow Ward",
  [36] = "Create Spellstone",
  [40] = "Howl of Terror; Summon Felsteed (riding)",
  [42] = "Death Coil",
  [48] = "Soul Fire",
}

-- Gear: levelling wands and the Warlock class-quest items. Wands matter most until about 30.
local GEAR = {
  { from = 10, to = 19, label = "Levels 10-19", slots = {
    { slot = "Wand", best = "Greater Magic Wand", src = "Enchanting (13) or the Auction House", alt = "Lesser Magic Wand", altsrc = "Enchanting (5) or the Auction House" },
  } },
  { from = 20, to = 29, label = "Levels 20-29", slots = {
    { slot = "Wand", best = "Gravestone Scepter", src = "Q: Blackfathom Villainy (Blackfathom Deeps)", alt = "Greater Magic Wand", altsrc = "Enchanting or the Auction House" },
    { slot = "Weapon", best = "Staff of Soran'ruk", src = "Class quest: Orb of Soran'ruk (/fp side), fragments from BFD and SFK", alt = "Orb of Soran'ruk", altsrc = "same quest, the off-hand choice" },
  } },
  { from = 30, to = 39, label = "Levels 30-39", slots = {
    { slot = "Wand", best = "Necrotic Wand", src = "Scarlet Monastery (?)", alt = "Gravestone Scepter", altsrc = "Q: Blackfathom Villainy" },
    { slot = "Chest", best = "Enchanted Gold Bloodrobe", src = "Class quest: Enchanted Gold Bloodrobe (/fp side), levels 31-38" },
    { slot = "Weapon", best = "Staff of Dar'Orahil", src = "Class quest: Orb of Orahil (/fp side), levels 35-40; or Staff of Noh'Orahil / an Orahil orb", alt = "Staff of Soran'ruk", altsrc = "Class quest: Orb of Soran'ruk" },
  } },
  { from = 40, to = 49, label = "Levels 40-49", slots = {
    { slot = "Wand", best = "Peacekeeper Wand", src = "(?) Warcraft Tavern's pick at 43", alt = "White Obsidian Wand", altsrc = "(?) at 39" },
  } },
  { from = 50, to = 60, label = "Levels 50-60", slots = {
    { slot = "Wand", best = "Wand of Biting Cold", src = "Quest reward, 51 (?)" },
    { slot = "Weapon", best = "Soul Harvester", src = "Class quest: An Imp's Request (/fp side), 50-54", alt = "Shard of the Green Flame", altsrc = "Class quest: Shard of the Green Flame, 50-56 (off-hand)" },
    { slot = "Chest", best = "Robes of Servitude", src = "Class quest: An Imp's Request (a choice with Soul Harvester and Abyss Shard)" },
  } },
}

local function Spec(name, desc, macros)
  return { name = name, desc = desc, macros = macros, training = TRAINING, gear = GEAR,
    macroNote = "Keys: 1 ATTACK, 2 DOTS, 3 DRAIN, 4 PET, 5 SELF. Thumb = Shift, pinky = Ctrl. Clear the game's own Shift+1-5 and Ctrl+1-5 bindings first." }
end

FP:RegisterClass({
  class = "WARLOCK",
  recommended = "affliction",
  specs = {
    affliction = Spec("Affliction (31/20/0)",
      "Instant Corruption, Bane of Agony and Siphon Life, then wand or drain. The fewest deaths; Wrack at 40.",
      Concat(ATTACK, DOTS_AFF, DRAIN_AFF, PET, SELF)),
    demonology = Spec("Demonology (20/31/0)",
      "A tougher Voidwalker, Soul Link at 30 and Demonic Pact at 40: your demon takes the hits.",
      Concat(ATTACK, DOTS_BASE, DRAIN_BASE, PET, SELF)),
    destruction = Spec("Destruction (19/0/32)",
      "Hardest hitting: Conflagrate at 26, Incinerate at 41. Needs more rest between pulls.",
      Concat(ATTACK_DESTRO, DOTS_DESTRO, DRAIN_DESTRO, PET, SELF)),
  },
})
