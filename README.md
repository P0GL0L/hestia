# Hestia

Open-source native macOS house-planning app. Apache-2.0.

Hestia is for anyone planning a house: draw the plan, see it in 3D, export a schematic drawing set, and edit the model through a chat agent. Exported sheets are schematic. They are not a sealed construction set and not a permit by themselves.

The product target is a Plan7Architect Pro-class feature set, built in parallel streams, without copying or reverse-engineering that product. DWG stays out of this repo. DXF is the open CAD path.

Former codename: ArchI-Tect. The product name is Hestia.

## Status

This repository is the system of record for contribution, monitoring, and completion.

Swift modules have not started. Stream 0 is the only stream that may begin. Every other stream waits for the `contracts-v1.0` tag.

- Work board: [issues](https://github.com/P0GL0L/hestia/issues)
- Assignments and done criteria: [docs/WORKSTREAMS.md](docs/WORKSTREAMS.md)
- Architecture locks: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Agent rules: [docs/AGENT-RULES.md](docs/AGENT-RULES.md)

## Who owns what

| Role | Party | Streams |
| --- | --- | --- |
| Owner. Approves contract changes, UI direction, name, and releases. | P0GL0L | — |
| Project manager. Dispatches, tracks, runs checkpoints. Does not merge or approve contracts. | Jarvis | Coordination |
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
