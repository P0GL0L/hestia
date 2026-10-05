# Stream 0 — Contracts

Owner: Claude. Start now. Close by tagging `contracts-v1.0`.

## Start point

This repository. Docs and the bootstrap CI exist. No Swift modules exist yet. That is intentional.

## Done when

- [ ] `Package.swift` declares every module in `docs/ARCHITECTURE.md`. Each compiles with stub implementations on Linux and macOS.
- [ ] The macOS app directory is `Apps/Hestia`, not the old codename.
- [ ] `ATContracts` defines `Length` (1/320 mm ticks), `Angle`, `Point2`, `Point3`, and unit formatting for feet-inches-fractions and metric.
- [ ] Model types with typed IDs: `Project`, `Building`, `Storey`, `Wall`, `Opening`, `Room`, `Stair`, `Roof`, `RoofPlane`, `Slab`, `Column`, `Beam`, `Placement`, `Layer`, `TerrainPatch`, `MEPSymbol`, `Sheet`.
- [ ] `model.json` v1 has `schemaVersion`. Encode and decode round-trip every fixture.
- [ ] `Command` protocol: validate, apply, inverse. v1 command catalog, each with a name, typed parameters, and a one-line description usable as an LLM tool description.
- [ ] Protocols and mocks: `GeometryEngine`, `DrawingGenerator`, `Exporter`, `Importer`, `LLMProvider`, `KeyStore`, `CatalogStore`.
- [ ] Display-list types and mesh types shared by drawings, exchange, and the 3D view.
- [ ] Fixtures: `rect-cottage`, `l-house`, `wall-joins`, as defined in `docs/ARCHITECTURE.md`.
- [ ] CI: Linux build plus tests, macOS build plus tests, SwiftLint, and a platform-rule check. Keep `CI / bootstrap` green.
- [ ] Tag `contracts-v1.0`.

## Out of scope

Geometry behavior, UI, exporters, provider calls, and catalog content. Stubs only.

## Do not

Leave commands as unnamed TODOs. If geometry later proves a command wrong, fix it with a labeled `contract-change` pull request.
