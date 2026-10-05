# Stream D — Drawings

Owner: Claude. Do not start before `geometry-v0.5`.

## Start point

Tag `geometry-v0.5`. Section-cut API and plan-view classification (cut versus beyond) work on `rect-cottage`.

## Done when

- [ ] Sheet sizes: ARCH C, ARCH D, ANSI B, ISO A1, ISO A3. Title block with project, address, sheet number, scale, date, and revision table.
- [ ] Scales 1/4 in = 1 ft, 1/8 in = 1 ft, 1:50, and 1:100. A line measured in the PDF is within 0.1 mm of the expected length.
- [ ] Floor plans with lineweights, wall hatches, door swings, window symbols, and room tags with name and area.
- [ ] Automatic dimension chains, exterior and interior, with editable overrides.
- [ ] Four elevations, at least one building section, roof plan, site plan, and electrical plan.
- [ ] Schedules: doors, windows, room finishes, area list.
- [ ] Sheet numbers: A-001, A-101+, A-201+, A-301+, A-601, E-101.
- [ ] Platform-free display list. Pure-Swift vector PDF writer.
- [ ] Every exported sheet is marked schematic / not for construction.
- [ ] Golden test: `rect-cottage` sheet set matches reviewed reference PDFs.
- [ ] Tag `drawings-v1.0`.

Claude also designs the Stream F tool schemas and system prompt, and integrates at each checkpoint.
