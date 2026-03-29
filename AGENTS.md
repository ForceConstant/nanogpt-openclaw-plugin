# AGENTS.md — NanoGPT Provider Plugin

> **Living document.** Update this as the project evolves — new decisions, completed phases, found gotchas, and architecture choices should be recorded here so any agent (or human) can pick this up and understand the current state instantly.

---

## Project Overview

**Name:** `@openclaw/nano-gpt`
**Type:** OpenClaw provider plugin (standalone npm package)
**Goal:** First-class NanoGPT support in OpenClaw — dynamic model catalog, API-key auth, usage tracking.
**Repo:** `http://git.search.dontexist.com/openclaw/nano-gpt-plugin`
**Status:** Planning complete; implementation pending.

---

## What This Is

A plugin that registers `nano-gpt` as an OpenClaw model provider. It lets OpenClaw:
1. Authenticate via `NANOGPT_API_KEY`
2. Pull the live model catalog from nano-gpt.com's API (no hardcoded lists)
3. Accept any nano-gpt model ID (e.g. `nano-gpt/anthropic/claude-opus-4.6`)
4. Track usage and balance from nano-gpt.com's usage endpoints

---

## File Structure

```
nano-gpt-plugin/
├── AGENTS.md              ← YOU ARE HERE (project state, decisions, conventions)
├── PLAN.md                ← Full implementation plan (source of truth)
├── package.json           ← npm package manifest
├── openclaw.plugin.json   ← Plugin manifest / auth config
├── src/
│   ├── provider.ts        ← Main provider implementation
│   ├── catalog.ts         ← Dynamic catalog fetcher
│   ├── types.ts           ← NanoGPT API type definitions
│   └── usage.ts           ← Usage + balance endpoint clients
└── tests/
    └── provider.test.ts   ← Unit tests (Vitest, mocked runtime)
```

---

## Key Decisions (Living)

| Decision | Value | Rationale |
|---|---|---|
| Package name | `@openclaw/nano-gpt` | Follows `@openclaw/<name>` convention |
| Provider ID | `nano-gpt` | Matches canonical service name |
| Base URL | `https://nano-gpt.com/api/v1` | Canonical nano-gpt endpoint |
| API compat | `openai-completions` | OpenAI-compatible endpoint |
| Auth | API key only (`NANOGPT_API_KEY`) | No OAuth; key is sufficient |
| Catalog strategy | Dynamic fetch on first use, cached for session | Avoids stale lists; no per-request refetch |
| Dynamic model resolution | Yes — `resolveDynamicModel` | Accepts any model ID user types |
| Usage tracking | Yes — `fetchUsageSnapshot` + `fetchBalance` | Daily/monthly limits + balance |
| Testing | Vitest + mocked `PluginRuntime` | No real OpenClaw instance needed |

---

## Testing Strategy

**Run tests with:**
```bash
pnpm test
# or scoped:
pnpm test -- tests/
```

**Test pattern (from OpenClaw SDK):**
- Use Vitest (`describe`, `it`, `expect`, `vi`)
- Mock the runtime via `createPluginRuntimeStore` + `as unknown as PluginRuntime`
- Use `vi.fn().mockResolvedValue(...)` for async mocks
- Import test utilities from `openclaw/plugin-sdk/testing` where applicable
- **No live OpenClaw instance required** — all tests use mocked/stubbed runtime

**What to test per phase:**
- Phase 1: Provider registration, hardcoded catalog, auth resolution
- Phase 2: Catalog fetch + field mapping
- Phase 3: Dynamic model resolution
- Phase 4: Usage snapshot + balance responses

---

## OpenClaw SDK Reference

Key docs: `/app/docs/plugins/sdk-provider-plugins.md`
Testing: `/app/docs/plugins/sdk-testing.md`

Key imports:
```typescript
import { defineSingleProviderPluginEntry } from "openclaw/plugin-sdk/provider-entry";
import { createPluginRuntimeStore } from "openclaw/plugin-sdk/runtime-store";
import type { PluginRuntime } from "openclaw/plugin-sdk/runtime-store";
```

---

## Current Phase

**Phase 0 (Done):** Research + planning
**Phase 1 (Next):** Skeleton + static provider — package scaffolding, hardcoded model list, auth flow, chat completions verification.

Do not proceed to Phase 2 without Brian's sign-off on Phase 1.

---

## Notes & Gotchas

- NanoGPT model IDs contain slashes (e.g. `anthropic/claude-opus-4.6`) — no splitting needed, pass as-is
- NanoGPT returns `pricing.prompt` and `pricing.completion` in $/million tokens — divide by 1,000,000 for OpenClaw's per-token cost
- `vision: true` in NanoGPT → map to `input: ["text", "image"]`
- `reasoning: true` in NanoGPT → map to `reasoning: true` on the model
- Catalog caching: fetch once per session on first model list request; don't refetch on every inference call

---

## How to Onboard (when implemented)

```bash
openclaw onboard --nano-gpt-api-key <key>
```

The plugin will auto-detect `NANOGPT_API_KEY` env var if set before onboarding.

---

## Integration Test Procedure

To run the nano-gpt-plugin integration test:  (Assuming working project directory is /workspace/nano-gpt-plugin)

1. Use scp to copy latest plugin to ssh_gateway /tmp directory  
2. Run these steps on ssh_gateway
    a. Set openclaw state directory: `mkdir -p /tmp/openclaw_state_$(date +%Y-%m-%d)`
    b. Ensure NANOGPT_API_KEY is set in environment (should already be configured on ssh_gateway)
    c. Install plugin to openclaw 
    d. Setup openclaw i.e. onboarding.
    e. Set default model to be nanogpt/nvidia/nemotron-3-super-120b-a12b
    f. Using openclaw send message using default agent of "Hello", and wait for response.
3. Back on main gateway
    a. Make results directory at workspace/nano-gpt-plugin/test_results/$(date +%Y-%m-%d)
    b. Using scp copy session files from ssh_gateway from <tmp state directory>/agents/main/session/*.jsonl
    c. Also in this results directory create a commands.md which contains each of the tool commands executed as part of this test.
4. Verify results contain expected reasoning and response
    - Pass/Fail Criteria: 
      a. The final assistant message object (type:"message" with role:"assistant") MUST have stopReason:"stop" (not "error")
      b. The message content MUST contain a text response (not empty)
      c. NOTE: usage.totalTokens may be 0 in current implementation as usage tracking is a future feature (see Phase 4 in Notes & Gotchas)
5. Update the "Integration Test Procedure" about any missing steps, or clarifications.
6. Commit/Push all files in /workspace/nano-gpt-plugin including any unstaged, or previously changed files.




