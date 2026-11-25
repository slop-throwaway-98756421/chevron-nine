# Content spec: greybox season (prototype step 1)

Source of truth for numbers is [`data/content.json`](../data/content.json); this page explains them.
Design doc: v0.1 (Landfall). **Every number here is a [Guess]** to be moved by playtesting.

The prototype answers one question: *is a single season, ending in a shipment score, fun enough to replay?*

## Season rules

| Rule | Value | Notes |
|---|---|---|
| Season length | 180 s at 1x | Design doc says ~5 min; shorter for faster playtest loops. Pause, 1x, 2x, 3x. |
| Grid | 16 × 12 | Depot in the centre, 3×3 landing zone kept clear. |
| Terrain | Plain, Ore deposit, Fertile soil, Rock | 2 ore + 2 fertile blobs (5–7 tiles); one of each within 3 tiles of the Depot. 5–8 rocks. |
| Start stock | 24 Ore, 6 Alloy, 8 Rations | Enough for 2–3 buildings plus roads. |
| Start crew | 8 workers | Habitats add 4 each. |
| Permits | 4 per season | Each card building costs 1 permit. Core buildings cost none. |
| Hand | 4 unique cards from the deck, 1 redraw | Season 1 always has a Mine and a Farm. Every hand has at least one card from each chain. |
| Resupply | +10 Ore, +2 Alloy, +4 Rations at the start of seasons 2+ | A floor so a bad shipment can't leave you with nothing to build with. |
| Warehouse reserve | 10 Ore, 4 Alloy | Processors won't pull the warehouse below this, so they can't eat your building budget. Adjacent hand-off and Habitats ignore it. |
| Seasons | Continue while you meet quota | Buildings and leftover goods carry over. New hand and permits each season. No shop yet. |

**Hand rule deviation from the doc:** the doc says a hand of 5 that you can build "as often as permits allow". With 6 card types, 5 cards nearly always shows everything, and duplicates are dead cards. So the greybox draws **4 unique types**. Worth checking in playtests.

## Logistics (adjacency + roads, no belts)

- A building is **linked to the Depot** if it touches the Depot or a road network that touches the Depot. Linked buildings drop outputs into, and fetch inputs from, the shared warehouse.
- **Adjacent hand-off:** a producer hands outputs straight to a touching building that needs them, before the warehouse. This works even without roads.
- **Linked bonus:** a processor touching a supplier of one of its inputs runs **+50%** faster.
- **Relay Pylon:** +25% speed to each touching production building; stacks.
- Output buffer holds 4 per good; a building with nowhere to send goods stalls ("Output full").
- Workers are assigned in build order. Buildings beyond the worker count stop ("No workers").

## Goods

| Good | Value | Tier | Made by |
|---|---|---|---|
| Ore | 1 | 1 | Mine |
| Alloy | 5 | 2 | Smelter |
| Machine Parts | 24 | 3 | Fabricator |
| Grain | 1 | 1 | Farm |
| Rations | 4 | 2 | Ration Mill (also eaten by Habitats) |

## Chain 1: Ore → Alloy → Machine Parts

| Building | Card | Cost | Workers | Recipe | Cycle | Placement |
|---|---|---|---|---|---|---|
| Mine | yes | 4 Ore | 2 | → 1 Ore | 3 s | Ore deposit |
| Smelter | yes | 8 Ore | 2 | 2 Ore → 1 Alloy | 4 s | Anywhere |
| Fabricator | yes | 6 Alloy | 3 | 2 Alloy → 1 Parts | 6 s | Anywhere |

Ratios at base speed: 1 Smelter wants 0.5 Ore/s = 1.5 Mines. 1 Fabricator wants 0.33 Alloy/s = 1.3 Smelters = 2 Mines. Value added per second: Mine 0.33, Smelter 0.75, Fabricator 2.3, so the deep end of the chain is where the points are, but it needs workers and therefore Habitats.

## Chain 2: Grain → Rations (feeds people)

| Building | Card | Cost | Workers | Recipe | Cycle | Placement |
|---|---|---|---|---|---|---|
| Farm | yes | 4 Ore | 1 | → 1 Grain | 2.5 s | Fertile soil |
| Ration Mill | yes | 6 Ore, 1 Alloy | 2 | 3 Grain → 2 Rations | 5 s | Anywhere |

## Core buildings (always available, no permit)

| Building | Cost | Effect |
|---|---|---|
| Road | 1 Ore | Links buildings to the Depot. Click-drag to paint. |
| Habitat | 6 Ore, 2 Alloy | +4 workers. Eats 1 Rations every 20 s (first meal on placement). Adds up to **+0.5 Prosperity mult**, scaled by the share of meals it got this season. |
| Demolish | — | Built this season: full refund, permit back (free undo). Older: 50% refund, and you keep a **salvaged blueprint** that rebuilds that building once, anywhere, without the card or a permit. |

The single population tier (Settlers) is the Habitat. The core trade-off: Rations are worth 4 each when shipped, but every Ration eaten keeps a +0.5 mult alive.

## Starter deck (14 cards)

Mine ×3, Smelter ×2, Fabricator ×2, Farm ×3, Ration Mill ×2, Relay Pylon ×2.

Relay Pylon: 4 Alloy, 0 workers, +25% speed to touching production buildings.

## Scoring

At season end the gate opens. You choose how much of each good to ship with a slider (All / None shortcuts); the rest stays for next season.

**Score = Σ(qty × value) × Prosperity**, Prosperity = 1.0 + 0.5 × Σ(fed share of each Habitat).

Then a count-up: each line ticks up, then value, then × mult, then the score counts toward the quota and shakes.

## Quota curve

`quota(n) = round10(150 × 1.6^(n−1))`, × 1.25 on boss seasons (every 4th).

| Season | 1 | 2 | 3 | 4 (boss) | 5 | 6 | 7 | 8 (boss) |
|---|---|---|---|---|---|---|---|---|
| Quota | 150 | 240 | 380 | 770 | 980 | 1,570 | 2,520 | 5,030 |

1.6× per season is a bit above the doc's 1.5× because buildings carry over and compound. Boss seasons only raise the number in this build; boss rule changes come with step 3.

**Balance check** (`--balance` in the test runner, a greedy bot over 30 seeds that ships everything): season 1 median 294 vs quota 150 (min 226, max 443); most bot runs die at the season 4 boss. A human who keeps materials and feeds Habitats should reach season 4–6. The wide spread in season 1 comes from the hand draw, which is the first thing to watch in playtests.

## Starter Charters (for step 2, not in this build)

Rule-breakers in 5 slots, bought in the shop. Each one hooks into a system that already exists in the greybox.

| # | Charter | Rarity | Effect | Hook |
|---|---|---|---|---|
| 1 | Company Town | Common | Each Habitat touching a production building: +0.25 mult | adjacency |
| 2 | Assay Contract | Common | Ore is worth 3 instead of 1 | goods value |
| 3 | Prospector's Claim | Common | Mines touching another Mine produce +1 Ore per cycle | adjacency |
| 4 | Vertical Integration | Uncommon | +0.1 mult for every Linked building | linked bonus |
| 5 | Overclock Doctrine | Uncommon | Production +50% speed; each cycle has a 3% chance to jam for 10 s | speed |
| 6 | Lean Crews | Uncommon | Buildings need 1 fewer worker; Habitats house 2 fewer | workers |
| 7 | Bread and Circuits | Uncommon | Machine Parts +2 value per fully fed Habitat | needs × chain 1 |
| 8 | Monoculture | Rare | If the shipment is a single good type, score ×3 | shipment choice |
| 9 | Duty-Free Gate | Rare | The first 20 units of each good shipped count double | shipment choice |
| 10 | Debt Ledger | Cursed | +5 credits per season; quota growth becomes 1.8× | quota curve |

Intended combos: Prospector's Claim + Assay Contract (ore spam), Monoculture + a Parts-only engine, Company Town + Vertical Integration (dense layouts), Lean Crews + Bread and Circuits.

## Anti-brick rules (after Marcus's first playtest)

Runs bricked too easily: demolishing lost the blueprint, hands could miss a whole chain, and all-or-nothing shipping forced a choice between bricking and failing the quota. Fixes: chain-covering hands, salvaged blueprints and free same-season undo, partial shipping, a small resupply, and a warehouse reserve.

With these, the greedy bot (ships everything) now usually reaches the season 4 boss: 21 of 30 runs fail there, versus most failing in season 2–3 before.

## Open questions

1. Season length: 180 s here vs ~5 min in the doc. Which feels right once you've played a few?
2. Are the anti-brick rules too generous now? The resupply in particular could be cut once the shop exists.
3. Is shipping Rations (worth 4) vs feeding Habitats (+0.5 mult each) an interesting choice, or obvious?
