# Agent rules

You are working in Hestia, the open-source macOS house-planning app. The GitHub repository is the system of record. Notion is not.

## Identity

- Product name: Hestia.
- Owner: P0GL0L. Approves contract changes, UI direction, the name, and releases.
- Project manager: Jarvis. Coordinates. Does not merge, does not edit product code, and does not approve contracts.
- Read your assignment in `docs/WORKSTREAMS.md` before editing.

## Ownership

| Party | Streams | Brief |
| --- | --- | --- |
| Claude | 0 Contracts, D Drawings, F tool design | `docs/briefs/stream-0-contracts.md`, `docs/briefs/stream-d-drawings.md` |
| Claude Code | A Geometry | `docs/briefs/stream-a-geometry.md` |
| Cursor | B App shell and 2D, C 3D | `docs/briefs/stream-b-app-2d.md`, `docs/briefs/stream-c-3d.md` |
| Grok CLI | E Exchange, F adapters and MCP | `docs/briefs/stream-e-exchange.md`, `docs/briefs/stream-f-agent.md` |
| Any agent | G Catalog | `docs/briefs/stream-g-catalog.md` |

Do not start another party's stream. Stream 0 is the only open start. A–G wait for tag `contracts-v1.0`.

## Hard rules

- One module per stream. Do not edit another module except through a `contract-change` pull request.
- No AppKit, SwiftUI, RealityKit, CoreGraphics, or Keychain under `Sources/`. Apple frameworks live only under `Apps/`.
- Lengths are integer ticks once `Length` exists. No `Double` lengths in the model.
- No direct model mutation. Commands only.
- No Plan7Architect code, assets, or reverse-engineered formats.
- No secrets in git, issues, or logs.
- Drawings and framing displays are schematic and non-engineered. Do not label output as permit-ready or contractor-certified.

## Pull requests

Branch `stream/<letter>-<topic>`. Target `main`. Green CI. Link the stream issue. Jarvis does not merge.
