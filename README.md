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

## Who owns what

| Role | Party | Streams |
| --- | --- | --- |
| Owner. Approves contract changes, UI direction, name, and releases. | P0GL0L | — |
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
