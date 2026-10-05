# Stream F — Provider adapters and MCP

Owner: Grok CLI. Tool schemas and the system prompt are designed by Claude. Do not start the adapter implementation before `contracts-v1.0`. Do not invent tool schemas if Claude's schema note is missing; ask Jarvis to chase it.

## Start point

`contracts-v1.0` `LLMProvider`, `KeyStore`, and command catalog. Claude's tool schemas and system prompt.

## Done when

- [ ] Anthropic adapter with streaming and tool use.
- [ ] OpenAI-compatible adapter with streaming and tool calls. Configurable base URL so one adapter serves OpenAI, xAI Grok, and local Ollama.
- [ ] Gemini adapter with streaming and function calling.
- [ ] Tool definitions generated from the command catalog, plus read tools: project summary, list rooms, measure, get element, render plan snapshot.
- [ ] Agent loop: the model proposes a batch of commands. The app shows a diff preview. The user accepts or rejects. Accepted batches are one undo step. Cap of 50 commands per turn.
- [ ] API keys are read only through `KeyStore`. The Keychain implementation stays in the app, not in `Sources/`.
- [ ] `hestia-mcp` executable: an MCP stdio server exposing the same tools against a project file.
- [ ] Eval suite of 25 scripted requests. Each hosted provider that has a funded test key passes at least 90 percent. Local-model results are reported, not gated.
- [ ] Network failures, rate limits, and invalid tool calls surface as readable errors and never corrupt the model.

## Out of scope

Spending-cap setup and secret storage in GitHub Actions. Those stay with P0GL0L. Never print a key.
