# Craftseeker
Craftseeker is a reagent and recipe browser for WoW: Forever, laid out like the profession window.

Alt+Click any crafting reagent in your bags to see every recipe it goes into, how to learn each one, and where to get the reagent — vendors, drops, gathering and chests, with drop rates measured by players.

<img width="1031" height="775" alt="image" src="https://github.com/user-attachments/assets/7533968a-84de-4faf-aeec-1d68082ed020" />

---
What it shows:

- Every recipe that uses a reagent, grouped by profession
- The recipes that make an item (right-click it)
- How to learn each recipe — trainers, vendors, drops and quests
- Where to get a reagent — vendors with prices, creatures with drop rates, skinning, mining, herbs and chests
- Skill-up arrows, like the profession window
- Which of your characters know a recipe
- How many of each reagent you carry, in your bags, bank and on your alts
- Map pins for trainers, vendors and creatures (TomTom too, when installed)

<img width="1031" height="778" alt="image" src="https://github.com/user-attachments/assets/d869eef9-2a24-4be4-a0f3-d5f7a056ee1f" />

---

The start page lists the reagents in your bags and bank. Search for any reagent, recipe or crafted item, and narrow every list with the Filter button: your professions only, recipes with a skill-up, recipes you don't know yet, or recipes you have the materials for. Favorite a recipe to keep it at the top, or track it in the objective tracker.

<img width="1041" height="781" alt="image" src="https://github.com/user-attachments/assets/bddf3152-b3a0-4453-8c48-45ad25e8186d" />

---

Drop rates keep improving as you play. Every corpse you loot and every node you gather is counted, and Craftseeker shares those counts with other Craftseeker users online — both factions, your guild, group and friends. It also reads the counts Drop Tables and Forever Drops users share, and fills in levels, zones and vendor prices the game data leaves blank.

<img width="272" height="123" alt="image" src="https://github.com/user-attachments/assets/af5c168e-70e4-47ed-8814-5c8a6236b73f" />

Reagents in your bags and bank get one line in their tooltip, saying how many recipes use them; nothing else touches item tooltips.

<img width="283" height="177" alt="image" src="https://github.com/user-attachments/assets/e3354add-ab24-40c7-8866-3acfc5ea3d33" />

---

## Commands:

- ` /cs ` — Open Craftseeker
- ` /cs <item link, ID or name> ` — Look up a reagent, recipe or crafted item
- ` /cs options ` — Open the settings
- ` /cs minimap ` — Show / hide the minimap button
- ` /cs share ` — Turn sharing with other Craftseeker users on / off
- ` /cs status ` — Check whether sharing reaches other players
- ` /cs hello ` — Announce yourself to other Craftseeker users now
- ` /cs stats ` — What's been learned so far
- ` /cs reset ` — Wipe all learned data
---

## FAQ

**Q: Why are some drop rates missing?**

**A:** A rate shows once someone has looted that creature. Rare drops often have no measured rate yet; they fill in as you and other players loot.

<br>

**Q: Why don't I see the opposite faction's recipes?**

**A:** The factions can't trade, so those recipes are hidden. Tick "Show opposite faction" in the settings to list them; they carry the opposite faction's emblem.

<br>

**Q: How do I know which recipes I already know?**

**A:** Recipes you know get a check mark, read from your spellbook at login. A blue name means one of your alts knows it — hover it to see who.

<br>

**Q: Sharing doesn't seem to work.**

**A:** Run `/cs status`. It says whether the hidden channel passed its self-test and what was heard and sent this session. "Show debug messages" in the settings prints more.

---

## Credits

- Drop rates and skinning: Drop Tables contributors, https://github.com/valcheffnet/DropTables (CC BY-SA 4.0), and the Polestar authors' Recorder sessions, https://github.com/fitzforge/polestar (CC BY 4.0). The rate, gathering and creature-place tables are shared under CC BY-SA 4.0.
- Drop Tables' database also carries data from Blackthornes Farmer, https://github.com/Blackthornes/Blackthornes_Farmer (MIT), and Everloot, https://everloot.app (CC BY-SA 4.0).
- Recipe sources: WhatsTraining, https://github.com/fusionpit/WhatsTraining (MIT).
- Trainers, vendors and creature names: Data from Efficient Games (https://efficient.games), licensed under CC BY 4.0.
- Creature places, quest names and givers: AllTheThings, https://github.com/ATTWoWAddon/AllTheThings (MIT).
- Libraries: Ace3, LibDataBroker, LibDBIcon, ChatThrottleLib and LibDeflate, each under its own licence in `Libs`.
- Full notices: `LICENSE-DATA.md`.

## License
The code is MIT (`LICENSE`); data licences are in `LICENSE-DATA.md`.

Made for WoW: Forever.
