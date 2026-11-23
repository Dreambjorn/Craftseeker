# Data licences

## Drop rates

The table `R` in `Data.lua` (drop rates of recipe items) is adapted from two player-recorded WoW Forever
datasets and is shared under the Creative Commons Attribution-ShareAlike 4.0 International licence
(CC BY-SA 4.0, https://creativecommons.org/licenses/by-sa/4.0/).

Changes made by Craftseeker: counts reduced to recipe items only, the top five creatures per item kept,
chances worked out with Drop Tables' formula and rounded to hundredths of a percent.

### Drop Tables

Drop Tables contributors, https://github.com/valcheffnet/DropTables, licensed under CC BY-SA 4.0. Its
shared database carries these sources, whose notices stay with the data:

Blackthornes Farmer, harvested on the WoW Forever beta
(https://github.com/Blackthornes/Blackthornes_Farmer):

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

Data from Efficient Games (https://efficient.games), licensed under CC BY 4.0
(https://creativecommons.org/licenses/by/4.0/). Drop Tables changed it: only corpses looted solo and
corpses skinned without the Bountiful Harvest perk on the live servers, without quest items and items
the server doesn't show, summed over the builds and turned into Drop Tables counts.

Data from Everloot (https://everloot.app), CC BY-SA 4.0. Drop Tables changed it: only the loot and
skinning windows of creatures, without quest items, counted per install and turned into Drop Tables
counts, with names, levels and places from the NPC sightings.

### Polestar Recorder sessions

Contains data from "Polestar Recorder sessions" by the Polestar authors,
https://github.com/fitzforge/polestar (data/codex/recorded.json), licensed under Creative Commons
Attribution 4.0 (CC BY 4.0, https://creativecommons.org/licenses/by/4.0/). Changed by Craftseeker: only
rows marked trusted, only recipe items, used where Drop Tables has no rate. The Polestar authors do not
endorse Craftseeker.

## Trainers, vendors and creature names

The tables `T` and `V` in `Data.lua`, and creature names in `R`, use data from Efficient Games
(https://efficient.games), licensed under CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/):
EG Link's WoW Forever trainers, vendors, NPCs and creature details,
https://github.com/JIVESCORP/eg-link-output-wowf. Changed by Craftseeker: merged over every client
build, reduced to recipes, recipe items and reagents, with the cheapest price and first recorded place.

## Creature places and quests

The tables `Z` and `Q` in `Data.lua` hold where creatures are and which quests teach recipes, with their
names and givers. Instance names, quest names, givers and places come from AllTheThings' WoW Forever
database, https://github.com/ATTWoWAddon/AllTheThings (`.contrib/.db/forever`), read as text and reduced to
those facts, under its licence:

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

The maps players killed creatures on come from the Drop Tables shared database (CC BY-SA 4.0, see above).

## Everything else

Recipe names, reagents, items, recipe items and automatically learned recipes come from the game client's data tables. Which recipes exist on Forever
and how each is learned (the table `S` in `Data.lua`) come from WhatsTraining's Forever recipe files,
https://github.com/fusionpit/WhatsTraining, under its licence:

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

Creature, vendor and quest names shown in game are read from an installed QuestieDB; none of it is stored here.
