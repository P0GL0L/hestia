# Hestia

Open-source native macOS house-planning app. Apache-2.0.

Hestia is for anyone planning a house: draw the plan, see it in 3D, export a schematic drawing set, and edit the model through a chat agent. Exported sheets are schematic. They are not a sealed construction set and not a permit by themselves.

The product target is a Plan7Architect Pro-class feature set, built in parallel streams, without copying or reverse-engineering that product. DWG stays out of this repo. DXF is the open CAD path.

Former codename: ArchI-Tect. The product name is Hestia.

## Status

This repository is the system of record for contribution, monitoring, and completion.

The six Swift modules and the macOS app are built, and the [alpha bar](docs/ALPHA.md) is met: a new user can draw a six-room cottage with doors, windows, rooms, a hip roof, and a straight stair, orbit it in 3D, and export a schematic PDF and DXF. Work proceeds one reviewed slice at a time toward the full set of stream briefs. The `contracts-v1.0` tag that closes Stream 0 is not cut yet; [docs/WORKSTREAMS.md](docs/WORKSTREAMS.md) lists what remains.

- Alpha bar and merge authority: [docs/ALPHA.md](docs/ALPHA.md)

- Work board: [issues](https://github.com/P0GL0L/hestia/issues)
- Assignments and done criteria: [docs/WORKSTREAMS.md](docs/WORKSTREAMS.md)
- Architecture locks: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Agent rules: [docs/AGENT-RULES.md](docs/AGENT-RULES.md)

## Using the app

The app opens on the sample cottage, furnished and on its lot. The plan and the 3D view sit side by side; the picker at the top right shows the plan, both, or 3D alone.

- **Draw.** Room drags out a rectangle and makes four walls and the room inside them; rooms drawn side by side share walls. Wall draws connected walls, click by click; type a length such as `12'6` and press Return for an exact wall, and press Esc or right-click to stop. Lengths show as you draw.
- **Furnish and landscape.** Furniture places beds, sofas, kitchens, baths, and more; R turns the item. Site drags out the lot, lawn, driveway, paths, patio, deck, gravel, a pond, or a garden bed; trees, shrubs, and a car are under Furniture > Outdoor.
- **Edit.** Select picks a wall, an item, or an area; drag moves it (joined walls follow), R turns an item, and Delete removes it. Scroll or pinch to zoom the plan, and pan with two fingers.
- **Photos and other 3D tools.** Render Photo makes a photoreal still, outside or in, with Blender's Cycles renderer, using free CC0 materials, furniture, trees, and sky from Poly Haven. Blender is free and installed separately; Hestia runs it in the background. Export USD writes the house as OpenUSD for Blender, Maya, 3ds Max, Houdini, and renderers such as Arnold and V-Ray. See [docs/RENDERING.md](docs/RENDERING.md).
- **See it.** The 3D view stands the house upright on its site in daylight. Drag to turn it, scroll to zoom, and clear Roof to look down into the rooms. Walk Inside puts you at eye height in the largest room: W A S D or the arrows move, drag to look, Shift runs, and Esc stops. Walls stop you; doors let you through.

## Who owns what

| Role | Party | Streams |
| --- | --- | --- |
| Owner. Approves contract changes, the name, and releases. Ordinary UI slices need no approval; Charles is required only for real-money spend or a 2FA or login block (`docs/ALPHA.md`). | P0GL0L | — |
| Project manager. Specifies and dispatches slices, tracks, runs checkpoints, and merges verified green slices. Does not approve contract changes. | Jarvis | Coordination |
| Architect and integrator. | Claude | 0 Contracts, D Drawings, F tool design |
| Core geometry. | Claude Code | A Geometry |
| Mac UI. | Cursor | B App shell and 2D, C 3D viewport |
| Exchange and provider adapters. | Grok CLI | E Exchange, F adapters and MCP |
| Catalog, terrain, symbols. | Any agent with capacity | G |

## How to contribute

1. Read the brief for your stream in [docs/briefs](docs/briefs).
2. Branch from `main` as `stream/<letter>-<topic>`.
3. Open a pull request. Do not push to `main`.
4. Tick the issue checklist only when the proof exists and CI is green.

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[Apache-2.0](LICENSE). Bundled assets must be CC0 or equivalent, with the license recorded beside the asset.
