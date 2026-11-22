# Reagent Scout (WoW: Forever)

Alt+Click any crafting reagent to see every recipe it goes into, how to learn each one, and where you've found the reagent before. Item tooltips are left untouched.

## Install
1. Unzip so you have `World of Warcraft\_forever_\Interface\AddOns\ReagentScout\ReagentScout.toc`
2. Restart the game (or `/reload` if it was already running when you copied it in).

## How it learns
- **Built-in recipes:** `Data.lua` holds every Forever profession recipe (about 2,200) with its reagents, and how it is learned: trainer and cost, recipe item, vendor zones, quests, reputation and Merchant's Favor. Every reagent works from the first login.
- **QuestieDB (optional):** when Questie's database addon is installed, recipe items list the creatures that drop them (with level, rank and zone), the vendors that sell them by name and zone, and the quests that reward them. Reagents list their vendors too. Nothing is copied from it; it is read in game.
- **Faction:** recipes only the other faction can learn are hidden, and so are the other faction's vendors and quests.
- **Profession windows:** opening one of your profession windows marks which recipes each character knows, adds any recipe the game data missed, and hides built-in recipes that window does not list.
- **Linked professions:** a profession link from chat adds its recipes too.
- **Sources:** once an item is a known reagent, the addon records the vendors that sell it (with price), the mobs that drop it, the nodes you gather it from, and the zones you fish it in.

## Using it
- **Alt+Click** an item in your bags to open the browser. It looks like the profession window: recipes grouped by profession on the left, the selected recipe's reagents and how to learn it on the right.
  - Green: this character knows it. Yellow: an alt knows it. Grey: none of your characters know it yet.
- `/rs` opens the browser. Type a name, or Shift+Click an item into the search box.
- `/rs help` lists the commands. `/rs stats` shows what's been learned so far.

## Code layout
Built on Ace3 (`Libs\`): AceAddon for the addon object and modules, AceDB for saved data, AceEvent and AceBucket for events, AceConsole for `/rs`.

- `Core.lua` - addon object, saved-data defaults, slash commands
- `Recipes.lua` - recipe index, lookups, faction filter
- `Questie.lua` - creature, vendor, object and quest sources from QuestieDB's public API (contract 4)
- `Data.lua` - generated recipe data; do not edit by hand
- `Format.lua` - recipe and source text for the browser
- `Scanner.lua` - module: learns from profession windows
- `Sources.lua` - module: records vendors, loot, gathering and fishing
- `Browser.lua` - module: the window
