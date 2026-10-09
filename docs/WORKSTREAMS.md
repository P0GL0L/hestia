# Workstreams

GitHub issues are how a stream is monitored and closed. This file is the assignment. The matching issue is the checklist you tick.

Nothing is done until its issue checklist is ticked and CI is green.

## Assignment

| Stream | Owner | Start | Close tag |
| --- | --- | --- | --- |
| 0 Contracts | Claude | Started. Open items are in the Stream 0 brief's checklist. | `contracts-v1.0` |
| A Geometry | Claude Code | `contracts-v1.0` | `geometry-v0.5`, then `geometry-v1.0` |
| B App shell and 2D | Cursor | `contracts-v1.0` and the mock `GeometryEngine` | App done criteria in the issue |
| C 3D viewport | Cursor | `contracts-v1.0` mesh types. Real meshes at `geometry-v0.5`. | App done criteria in the issue |
| D Drawings | Claude | `geometry-v0.5` | `drawings-v1.0` |
| E Exchange | Grok CLI | `contracts-v1.0` | Exchange issue |
| F Adapters and MCP | Grok CLI | `contracts-v1.0`, plus Claude's tool schemas | Agent issue |
| G Catalog | Any agent Jarvis assigns | `contracts-v1.0` | Catalog issue |

Jarvis dispatched Stream 0 first. Since `docs/ALPHA.md` set the alpha bar and merge authority, Jarvis dispatches slices in any stream toward that bar; the checkpoints below remain the plan for the full release, and `contracts-v1.0` still closes Stream 0.

## Checkpoints

| Checkpoint | Week target | Must be merged | Pass test |
| --- | --- | --- | --- |
| I1 Contracts | 1 | `contracts-v1.0` | Every module stub builds on Linux and macOS. Fixtures round-trip. |
| I2 Walkable house | 4 | `geometry-v0.5`, B canvas basics, C basic viewport, E DXF and glTF | `rect-cottage` drawn in the app, orbitable in 3D, exported to DXF and `.glb`. |
| I3 Core complete | 8 | `geometry-v1.0`, C done, F adapters, G first 150 items | `l-house` builds with the roof and stair types in scope. The agent adds a door through each provider then in scope. |
| I4 Feature complete | 12 | All streams | Full sheet set exports. Feature freeze starts. |
| RC | 14 | Fixes only | Final acceptance issue, run by P0GL0L. |

Week targets are planning marks, not proof. A failed checkpoint stops the streams that depend on it. Jarvis posts pass or fail. P0GL0L decides go or slip.

## Merge rules

- Order: 0, then A, then B, C, E, F, and G in parallel, then D.
- `main` stays green. A red `main` stops merges until it is fixed.
- Rebase onto `main` daily.
- After I4, only bug fixes merge.

## Still owner-gated, not stream work

- Apple Developer membership, signing, and notarizing.
- Provider API keys and spend limits.
- Agent GitHub identities, if they should push as themselves rather than as P0GL0L.
- Trademark, domain, and name clearance before a public release. The repo name is already Hestia.
