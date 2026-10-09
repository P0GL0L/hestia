# Agent rules

You are working in Hestia, the open-source macOS house-planning app. The GitHub repository is the system of record. Notion is not.

## Identity

- Product name: Hestia.
- Owner: P0GL0L. Approves contract changes, UI direction, the name, and releases.
- Project manager: Jarvis. Coordinates, specifies each slice, and merges verified green slices (`docs/ALPHA.md`, Authority). Does not edit product code and does not approve contract changes.
- Read your assignment in `docs/WORKSTREAMS.md` before editing.

## Ownership

| Party | Streams | Brief |
| --- | --- | --- |
| Claude | 0 Contracts, D Drawings, F tool design | `docs/briefs/stream-0-contracts.md`, `docs/briefs/stream-d-drawings.md` |
| Claude Code | A Geometry | `docs/briefs/stream-a-geometry.md` |
| Cursor | B App shell and 2D, C 3D | `docs/briefs/stream-b-app-2d.md`, `docs/briefs/stream-c-3d.md` |
| Grok CLI | E Exchange, F adapters and MCP | `docs/briefs/stream-e-exchange.md`, `docs/briefs/stream-f-agent.md` |
| Any agent | G Catalog | `docs/briefs/stream-g-catalog.md` |

The table names each stream's default owner. Since `docs/ALPHA.md`, Jarvis may assign a slice in any stream to any party; work only on a slice you have been assigned, and only on the files its spec names. Until `contracts-v1.0` is tagged, streams advance slice by slice under that authority.

## Hard rules

- A slice touches the modules its spec names. A change to a public `ATContracts` type, command, or protocol is a `contract-change` and needs P0GL0L's approval.
- No AppKit, SwiftUI, RealityKit, CoreGraphics, or Keychain under `Sources/`. Apple frameworks live only under `Apps/`.
- Lengths are integer ticks once `Length` exists. No `Double` lengths in the model.
- No direct model mutation. Commands only.
- No Plan7Architect code, assets, or reverse-engineered formats.
- No secrets in git, issues, or logs.
- Drawings and framing displays are schematic and non-engineered. Do not label output as permit-ready or contractor-certified.

## Pull requests

Branch `stream/<letter>-<topic>`. Target `main`. Green CI. Link the stream issue. Jarvis merges when CI is green and the slice's evidence checks out; contract changes also need P0GL0L's approval.
