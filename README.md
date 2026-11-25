# Landfall (working title): greybox prototype

A roguelike city builder: production chains that turn into a Balatro-style score, shipped through a gate against escalating quotas.

This is **prototype step 1**: one grid, two production chains, a random blueprint hand, a quota and the score count-up. Grey boxes only. It tests one thing: is a season fun enough to replay?

- Content and numbers: [`docs/content-spec.md`](docs/content-spec.md) (data lives in [`data/content.json`](data/content.json), edit it to tune)
- Engine: Godot 4.3+

## Run it

Open the folder in Godot 4.3 and press F5, or:

```sh
godot --path .                    # random seed
godot --path . -- --seed=1234     # fixed seed, to replay the same map and hands
```

## How to play

1. The season starts paused. Look at your hand, the terrain and the quota.
2. Build. Cards from the hand cost 1 permit each; Roads and Habitats are always available.
3. Press **Space** to run time (+/- or the buttons for 2x and 3x). Keep building while it runs.
4. When the gate opens, untick anything you want to keep, then ship and watch the count-up.
5. Meet the quota and the next season starts with a new hand. Miss it and the run ends.

| Key | Action |
|---|---|
| Space | Pause / run |
| + / - | Speed |
| 1–4 | Pick a card from the hand |
| R / H / X | Road / Habitat / Demolish |
| Esc, right-click | Cancel tool |
| Enter | Ship / skip count-up / next season |

Reading the map: orange outline means not linked to the Depot. Blue `+` means Linked (+50% speed from a touching supplier). The dot is green when working, yellow when waiting for input, red when stalled. Hovering a tile with a tool highlights in blue the neighbours that would give it a bonus.

## Tests

```sh
godot --headless --path . --import                                     # first time only
godot --headless --path . --script res://tests/run_tests.gd            # unit checks
godot --headless --path . --script res://tests/run_tests.gd -- --balance   # + bot balance report
```

`tests/screenshot.gd` renders screenshots of a bot-played season (needs a display or `xvfb-run`).

## Layout

| Path | What |
|---|---|
| `scripts/sim.gd` | Deterministic tick simulation (no nodes). All rules live here. |
| `scripts/main.gd` | HUD, tools, shipment screen and count-up. UI is built in code. |
| `scripts/grid_view.gd` | Draws the grid and forwards mouse input. |
| `data/content.json` | Goods, buildings, deck, quota curve, season rules. |
| `tests/` | Headless tests, a greedy bot, screenshot script. |
