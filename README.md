# Reagent Scout (WoW: Forever)

Alt+Click any crafting reagent to see every recipe it goes into, how to learn each one, and where you've found the reagent before. Item tooltips are left untouched.

## Install
1. Unzip so you have `World of Warcraft\_forever_\Interface\AddOns\ReagentScout\ReagentScout.toc`
2. Restart the game (or `/reload` if it was already running when you copied it in).

## How it learns
- **Built-in recipes:** `Data.lua` holds every Forever profession recipe (about 2,200) with its reagents, and how it is learned: trainer and cost, recipe item, vendor zones, quests, reputation and Merchant's Favor. Every reagent works from the first login.
- **QuestieDB (optional):** when Questie's database addon is installed, recipe items list the creatures that drop them (with level, rank and zone), the vendors that sell them by name and zone, and the quests that reward them. Reagents list their vendors too. Nothing is copied from it; it is read in game.
- **Drop rates:** for about 120 recipe items, the chance per creature that WoW Forever players measured (Drop Tables and Polestar recordings), with the kills it is based on. Rare drops often have no measured rate yet.
- **Trainers and vendors:** the trainers and vendors WoW Forever players saw (EG Link), by name, zone and price.
- **Quests and places:** quests that teach a recipe, with who gives them and where, and the zone or instance of each creature (AllTheThings, Drop Tables).
- **Your own loot:** every corpse you loot is counted, so drop rates keep improving as you play; your counts are added to the built-in ones.
- **Sharing:** Reagent Scout users in your guild, your group and your friends lists (Battle.net friends too) trade their loot counts, so everyone's drop rates grow together. Your counts are announced when you log in, when you join a group or someone joins yours, when a friend comes online, and after new loot. Each user's counts are capped, and `/rs share` turns it off.
- **Faction:** recipes only the opposite faction can learn are hidden, and so are the opposite faction's vendors and quests. The factions can't trade, so a reagent only the opposite faction's recipes use says so.
- **Profession windows:** opening one of your profession windows marks which recipes each character knows, adds any recipe the game data missed, and hides built-in recipes that window does not list.
- **Linked professions:** a profession link from chat adds its recipes too.
- **Sources:** once an item is a known reagent, the addon records the vendors that sell it (with price), the mobs that drop it, the nodes you gather it from, and the zones you fish it in.

## Using it
- **Alt+Click** an item in your bags to open the browser. It looks like the profession window: recipes grouped by profession on the left, the selected recipe's reagents and how to learn it on the right. The right side scrolls: creatures, vendors and trainers are listed in tables, best drop rate first; hover a row for all its zones.
- **Click** an item in the window for the recipes that use it; **right-click** it for the recipes that make it.
  - Green: this character knows it. Yellow: an alt knows it. Grey: none of your characters know it yet.
- `/rs` or the minimap button opens the browser. Type a name, or Shift+Click an item into the search box.
- **Settings** are under Options > AddOns > Reagent Scout (`/rs options`, or right-click the minimap button): the minimap button, source tracking and sharing. `/rs minimap` shows or hides the button.
- `/rs help` lists the commands. `/rs stats` shows what's been learned so far, and from how many other users.

## Code layout
Built on Ace3 (`Libs\`): AceAddon for the addon object and modules, AceDB for saved data, AceEvent and AceBucket for events, AceConsole for `/rs`; LibDataBroker and LibDBIcon for the minimap button.

- `Core.lua` - addon object, saved-data defaults, slash commands
- `Recipes.lua` - recipe index, lookups, faction filter
- `Questie.lua` - creature, vendor, object and quest sources from QuestieDB's public API (contract 4)
- `Data.lua` - generated recipe data; do not edit by hand
- `Format.lua` - recipe and source text for the browser
- `Scanner.lua` - module: learns from profession windows
- `Sources.lua` - module: records vendors, loot, gathering and fishing, and counts looted corpses
- `Share.lua` - module: trades loot counts with other users (guild, group, friends; Forever refuses custom channels)
- `Browser.lua` - module: the window
- `Options.lua` - module: the settings page under Options > AddOns, and the minimap button

## Credits
- Drop rates: Drop Tables contributors, https://github.com/valcheffnet/DropTables (CC BY-SA 4.0), and the Polestar authors' Recorder sessions, https://github.com/fitzforge/polestar (CC BY 4.0). The rate table is shared under CC BY-SA 4.0.
- Recipe sources: WhatsTraining, https://github.com/fusionpit/WhatsTraining (MIT).
- Trainers, vendors and creature names: Data from Efficient Games (https://efficient.games), licensed under CC BY 4.0.
- Creature places, quest names and givers: AllTheThings, https://github.com/ATTWoWAddon/AllTheThings (MIT).
- Full notices: `LICENSE-DATA.md`.
