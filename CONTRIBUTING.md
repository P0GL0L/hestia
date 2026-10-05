# Contributing to Hestia

Hestia is one Swift package in one repository. You own your module. You do not widen the product by quietly editing someone else's stream.

## Before you start

- Stream 0 may start now.
- Streams A–G start only after `contracts-v1.0` exists.
- Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and your file in [docs/briefs](docs/briefs).
- Do not copy or reverse-engineer Plan7Architect: no code, icons, textures, catalog items, or file formats.

## Branches and pull requests

- Branch: `stream/<letter>-<topic>`
- Pull requests target `main`.
- Keep a PR to one behavior. About 600 changed lines is the normal cap. A geometry algorithm may exceed that if splitting it would fake the review. Say so in the PR.
- Touch only your module and its tests, unless the PR is a labeled `contract-change`.
- CI must be green: the `CI / bootstrap` check now, plus the Linux build, macOS build, tests, and SwiftLint once Stream 0 adds them.
- Tests for new behavior. No TODOs without a linked issue. Public API gets doc comments.
- Unfinished work merges behind a feature flag. Do not park it on a long branch.

## Contract changes

Any edit to `ATContracts`, `Package.swift`, or CI config:

1. Label the PR `contract-change`.
2. Claude reviews the design.
3. P0GL0L approves it.
4. Other streams rebase after it merges.

## Model rule

UI, agent, and import code never mutate the model directly. They submit `Command` values. Each command validates, applies, and returns its inverse for undo.

## Licensing

- Code in this repo is Apache-2.0.
- Every bundled asset is CC0 or equivalent. Record the license beside the asset.
- A license-audit failure is a failed build, once Stream G adds that check.
- Do not commit secrets, API keys, or Apple credentials.

## Completing work

The matching GitHub issue is done only when every box in that issue is checked and the proof link is in the issue. A green PR is not a closed stream.
