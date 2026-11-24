# Craftseeker data licences

Craftseeker's code is under the MIT License (`LICENSE`). This file covers the data in `Data.lua`, which is
generated from the sources below. Each source keeps its licence, and its notice is reproduced here. None of these sources endorses Craftseeker.

## Overview

| Table | What it holds | Sources | Licence of the table |
| --- | --- | --- | --- |
| `R` | Drop rates of recipe items, with creature names | Drop Tables, Polestar Recorder sessions, EG Link | CC BY-SA 4.0 |
| `G` | Gathering rates of reagents: skinned creatures, mining and herb nodes, chests | Drop Tables (skinning), Polestar Recorder sessions (objects) | CC BY-SA 4.0 |
| `Z` | Where each creature is | Drop Tables, AllTheThings | CC BY-SA 4.0 |
| `T`, `V` | Trainers and vendors, with prices and places | EG Link | CC BY 4.0 |
| `Q` | Quests that teach recipes, with givers and places | AllTheThings | MIT |
| `N` | Map pins | EG Link, AllTheThings | CC BY 4.0 |
| `S` | How each recipe is learned | WhatsTraining | MIT |
| `D`, `I`, `K`, `A`, `C`, `X` | Recipes, items, skill colours, zone maps, class spells, dungeon and raid names | Game client | Game data |

`R`, `G` and `Z` hold data adapted from CC BY-SA 4.0 sources, so they are shared under CC BY-SA 4.0
(https://creativecommons.org/licenses/by-sa/4.0/); anything made from them must be too. Craftseeker's own
changes to the other tables are under the MIT License, while the data they come from keeps the licence
named for it.

## Drop Tables

Drop Tables contributors, https://github.com/valcheffnet/DropTables, licensed under CC BY-SA 4.0.

- Used in: `R` (loot counts), `G` (skinning counts) and `Z` (the maps players killed each creature on).
- Changed by Craftseeker: loot counts reduced to recipe items and skinning counts to reagents, every creature with
  a count kept, chances worked out with Drop Tables' formula and rounded to hundredths of a percent.

Drop Tables' shared database carries data from three other sources, whose notices stay with it:

**Blackthornes Farmer**, harvested on the WoW Forever beta, https://github.com/Blackthornes/Blackthornes_Farmer.
Drop Tables took it from commit `43bc5ee7dada13896b358b33e6533182c36dbff0`, published under the MIT License:

```
MIT License

Copyright (c) 2026 Blackthornes

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

**Efficient Games**: Data from Efficient Games (https://efficient.games), licensed under CC BY 4.0
(https://creativecommons.org/licenses/by/4.0/). Changed by Drop Tables: only corpses looted solo and corpses
skinned without the Bountiful Harvest perk on the live servers, without quest items and items the server
doesn't show, summed over the builds and turned into Drop Tables counts.

**Everloot**: Data from Everloot (https://everloot.app), CC BY-SA 4.0. Changed by Drop Tables: only the loot
and skinning windows of creatures, without quest items, counted per install and turned into Drop Tables
counts, with names, levels and places from the NPC sightings.

## Polestar Recorder sessions

Contains data from "Polestar Recorder sessions" by the Polestar authors, https://github.com/fitzforge/polestar
(`data/codex/recorded.json`), licensed under CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/).

- Used in: `R`, for recipe items Drop Tables has no rate for, and `G` (mining nodes, herbs and chests).
- Changed by Craftseeker: only rows marked trusted with a chance, only recipe items (`R`) and reagents (`G`).

## EG Link

Data from Efficient Games (https://efficient.games), licensed under CC BY 4.0
(https://creativecommons.org/licenses/by/4.0/): EG Link's WoW Forever trainers, vendors, NPCs and creature
details, https://github.com/JIVESCORP/eg-link-output-wowf.

- Used in: `T`, `V`, the creature names in `R` and most map pins in `N`.
- Changed by Craftseeker: merged over every client build, reduced to recipes, recipe items and reagents, with
  the cheapest price and the first recorded place and position.

## AllTheThings

AllTheThings' WoW Forever database, https://github.com/ATTWoWAddon/AllTheThings (`.contrib/.db/forever`),
read as text and reduced to facts, under the MIT License:

```
MIT License

Copyright (c) 2026 AllTheThings WoW Addon

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- Used in: `Q` (quest names, givers and places), `Z` (instance names and places) and the map pins in `N`
  that EG Link has no position for.

## WhatsTraining

WhatsTraining's Forever recipe files, https://github.com/fusionpit/WhatsTraining, under the MIT License:

```
MIT License

Copyright (c) 2019

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- Used in: `S` (how each recipe is learned) and the list of which recipes exist on Forever.

A recipe is kept only with proof that it exists on Forever: one of the sources above, a Forever addition the
Classic Era client lacks, or both WoW Forever Tools and ForeverRecipes naming it with how it is learned. Of
those two lists only the recipe IDs are checked; nothing of them is shipped.

## Game client

Recipe names and reagents (`D`), item names and qualities (`I`), recipe items, automatically learned recipes,
skill colours (`K`), zone maps (`A`) and class spells with reagents (`C`) come from the game client's data
tables. Game data © Blizzard Entertainment, used as facts.

## Read in game, not shipped

- Creature, vendor and quest names from an installed QuestieDB; none of it is stored in Craftseeker.
- Loot counts that other players' Drop Tables and Forever Drops addons trade in game, read through those
  addons' own messages while playing and kept in the player's saved data. Nothing of either addon, code or
  data, is part of Craftseeker.
