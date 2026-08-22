# C Tutor Implementation Plan

## Goal

Provide a low-friction, learning-first C tutor inside Neovim through the official Meta Muse Spark 1.2 Contributor API. The tutor answers only explicit `// tutor:`, `// coach:`, `// t:`, and `// c:` questions, explains diagnostics on command, and never writes project code or turns source work into autocomplete.

## Non-negotiable boundaries

- Never edit or insert learner project source.
- No ghost text, completion acceptance, patches, diffs, shell, filesystem, LSP, browser, or agent tools.
- The default Meta credential is resolved by restricted OMP from `MODEL_API_KEY` or `META_API_KEY`; it never enters process arguments, prompts, response caches, or logs. The optional direct Gemini transport passes its key to `curl` over stdin.
- Code is sent only from eligible C buffers inside `.tutor` projects.
- Coach mode remains the default in eligible `.tutor` projects after the user's explicit authorization; `<leader>mt` can switch it off or into ask mode. Both enabled modes send only explicit marker questions or invoked commands.
- Ordinary Insert- and Normal-mode edits never trigger inferred coaching.
- Explicit reference capture updates only the `references` table in `.tutor/state.json` through validated atomic writes; model responses never change mastery or scheduling state.
- Model output is inert display text and can never be executed or inserted.

## Architecture

1. A language-profiled Neovim module observes supported explicit question markers and invoked diagnostic commands.
2. A privacy/context gate sends the complete numbered active buffer, strips absolute paths, rejects secret-bearing text anywhere in that buffer, and records the buffer `changedtick`.
3. The default transport keeps one restricted `omp --mode rpc` process warm, selects official `meta/muse-spark-1.2-contributor` with automatic thinking effort, and omits an OpenAI service tier. Tools, sessions, extensions, rules, skills, LSP, memory, advisor, compaction, and model fallback stay disabled. Direct Gemini Flash-Lite remains an explicit low-latency alternative rather than the default.
4. The client runs one model request at a time and keeps additional explicit requests in a FIFO queue. Every pending request has an invisible extmark anchor, so moving or deleting its marker updates the pending state before model work starts. Structured JSON is validated before rendering.
5. Each completed marker response has its own extmark, follows its comment as lines move, survives unrelated edits and buffer reloads, and is permanent while the exact marker remains. A deeper hint leaves the current decoration visible until its replacement is ready, then becomes the persisted decoration. Removing or changing the marker removes the decoration; tutor mode off clears all decorations. Tutor text never enters the buffer.

### Cross-device setup

- Install Neovim and OMP.
- Create an official Meta Model API key on each device and expose it to OMP as `MODEL_API_KEY` or `META_API_KEY`. Keep the key in a private credential file such as `~/.omp/agent/.env`, never in this repository or shell history.
- The committed default is `backend = 'omp'`, `model = 'meta/muse-spark-1.2-contributor'`, `service_tier = 'none'`, and `thinking_level = 'auto'`. Tutor requests have no wall-clock deadline; they remain cancellable by the user and still fail immediately if the model process exits or the transport reports an error.
- To use the faster Gemini route intentionally, configure `backend = 'gemini'`, `model = 'google/gemini-3.5-flash-lite'`, and `service_tier = 'priority'`; it requires `GEMINI_API_KEY` or `GOOGLE_API_KEY`.
- `.tutor/state.json` remains the portable project record. Reference add/use operations no longer depend on `~/.omp/agent/skills/tutor/scripts/tutor.py`.

## Interaction modes

### Off

No observation and no model requests.

### Ask

- `// tutor: <question>`, `// coach: <question>`, `// t: <question>`, and `// c: <question>` never start work during Insert mode. InsertLeave may start the stable marker after 250 ms; Normal-mode changes and save remain marker-only fallback triggers.
- Syntax recall receives one safest exact answer in at most 20 words, with no alternatives or retrieval question and only the smallest useful neutral example.
- Concept reasoning receives one decision axis or reasoning step in at most 24 words and one targeted question of at most 14 words, with no list or worked code.
- Classification is automatic; optional `syntax:` and `concept:` prefixes resolve ambiguity.
- `<leader>me` explains the root diagnostic at the cursor.
- When a tutor response asks a question, the annotation displays `<leader>mq`. That mapping opens a private editor prompt, submits the learner's answer with the preceding tutor response and current file context, then atomically replaces the question with concise feedback. A useful follow-up question can continue the same loop.
- `<leader>mm` requests one deeper explanation or hint; the successful result atomically replaces and persists as that marker's permanent decoration.
- `<leader>mu` / `:CTutorReroll` bypasses the selected response's cache entry. The existing decoration remains visible while the fresh request runs; success atomically replaces both the decoration and persisted cache entry.
- `<leader>mx` cancels active work or dismisses non-marker responses. Completed marker decorations require removing their `// tutor:`, `// coach:`, `// t:`, or `// c:` marker.

### Coach — default enabled mode in `.tutor` projects

- Uses the same explicit-marker contract as Ask mode. It never infers a question from an ordinary edit.
- Entering Insert mode cancels active and queued tutor work for that buffer. Insert-mode edits only reconcile existing permanent decorations; they never schedule a model request.
- Active work uses an orange framed tutor header with compact elapsed seconds. Completed annotations keep title, explanation, question, and learner-reply text white and bold. Generated examples carry an `AI <language>` badge and use that profile's Tree-sitter parser with a separate violet-backed neon palette; an unavailable parser or highlight query falls back to the same distinct AI panel instead of borrowing source-buffer colors.
- Every completed annotation has an orange provenance footer naming the exact model selector, configured thinking level or `no thinking`, and `fresh` or `cache hit`.

## Privacy and rate policy

- Eligible languages, filetypes, extensions, and parsers come from `lua/custom/tutor_languages.lua`; C and Swift are currently registered.
- Eligible roots must contain `.tutor/`.
- Exclude special buffers, hidden/credential files, ignored files, and source containing secret-like material.
- Send the project-relative path, the complete numbered active-buffer source, one relevant diagnostic, and minimal build metadata. No other project files are read automatically.
- Complete active-buffer source limit: 256 KiB. Larger buffers fail closed with an actionable message instead of silently sending a partial slice. Diagnostic metadata limit: 2 KiB.
- One request is in flight. Additional explicit marker requests wait in FIFO order; deleting a pending marker removes only that pending request.
- Explicit markers debounce for 250 ms after InsertLeave, Normal-mode changes, or save.
- Validated marker decorations, including the latest deeper hint, are cached by a SHA-256 key scoped to backend, exact model selector, thinking level, tutor root, project-relative file, and normalized question in `<stdpath('state')>/c-tutor/answers.json`. Switching models cannot silently reuse another model's answer. `<leader>me` diagnostic explanations use the same generation profile plus a fingerprint covering the project-relative file, diagnostic fields, anchor, and complete active-buffer context.
- Learner replies and reply feedback are session-only. They participate in the in-memory request queue and privacy checks but are never written to the persistent response cache or lifecycle log as raw text.
- The shared response cache is mode `0600`, capped at 256 entries, and restores the exact structured response, original elapsed time, generating model, thinking level, backend metadata, and generation timestamp without another model request. Cache keys persist only hashes: no source slice, raw marker question, diagnostic payload, prompt, provider credential, or model session is stored. Direct request bodies are temporary `0600` files inside the private tutor runtime directory and are unlinked after completion or cancellation. Cached tutor response text and provenance are persistent model content; structured lifecycle diagnostics contain only relative files, line numbers, editor events, queue/cache outcomes, model selectors, thinking levels, and truncated question hashes.

## Lifecycle diagnostics

- `<stdpath('state')>/c-tutor/events.jsonl` records UTC millisecond timestamps, a per-Neovim session identifier, monotonic sequence numbers, editor triggers, relative file/line locations, privacy-safe question identifiers, debounce outcomes, queue transitions, transport state, cache decisions, annotation removals, and mode changes.
- The log is mode `0600`, rotates to `events.jsonl.1` at 1 MiB during active sessions, and never stores source text or raw marker questions.
- `:CTutorLog` reports the active log path. `:CTutorStatus` reports tutor/backend/cache state.

## Structured response contract

Fields: `version`, `kind`, ask-only `help_kind`, `anchor_line`, `concept`, `title`, `explanation`, `question`, optional `neutral_example`, and `confidence`.

Kinds: `answer`, `hint`, `misconception`, `silence`.

Validation rules:

- Unknown versions, kinds, fields, oversized text, invalid anchors, control characters, or patch-shaped content fail closed.
- Explicit failures show a concise notification.
- Marker requests become stale only when their own extmark disappears, their comment question changes, or tutor mode is disabled. Unrelated `changedtick` updates do not invalidate them; non-marker commands retain changed-buffer protection.

## Delivery phases

### Phase 1 — Explicit tutor

- Restricted official Meta Muse Contributor RPC is the default; portable direct Gemini priority inference remains an explicit low-latency alternative.
- Explicit `// tutor:`, `// coach:`, `// t:`, and `// c:` detection.
- Bounded context construction and secret gate.
- Structured response parsing and virtual-line rendering.
- Off/ask modes, status, dismiss, retry, and process lifecycle.

### Phase 2 — Diagnostic coach

- Root diagnostic selection.
- Learning-first diagnostic explanation.
- One-step hint progression.
- Replace the obsolete local `wtf.nvim` diagnostic explainer after parity.

### Phase 3 — Persistent marker lifecycle

- Marker-only Insert/Normal triggers, per-marker debouncing, FIFO pending work, explicit active cancellation, permanent completed decorations, and root-wide mode transitions.
- Independent extmarks for active, pending, and completed questions; movement-safe rendering; atomic deeper-hint replacement; deletion/reintroduction reconciliation; exact decoration cache restoration; structured lifecycle diagnostics.

### Phase 4 — Tutor integration and cleanup

- Direct, atomic reference capture in `.tutor/state.json`; no OMP tutor-script dependency.
- Update the shortcut key bank.
- Remove duplicate explanation configuration and scaffolding.

## Verification

- Deterministic fake-transport checks for direct Gemini request encoding, stdin-only credential handling, bounded HTTP errors, OMP compatibility, framing, schema validation, priority-tier startup, complete-buffer context, Insert-mode non-dispatch and cancellation, per-marker debounce coalescing, unrelated edits, permanent-decoration movement, atomic deeper-hint replacement, marker deletion and reintroduction, pending/active cancellation, buffer unload and eligibility loss, split-window cursor selection, multi-buffer mode changes, exact marker and diagnostic cache restoration, diagnostic cache invalidation, corrupt persistence, timeouts, process failure, and clean shutdown.
- Policy fixtures for syntax questions, diagnostics, cascade errors, project-solution requests, prompt injection, oversized context, and secret rejection.
- Embedded headless Neovim smoke tests for marker-only Insert/Normal triggers, extmark rendering, mode transitions, cache reload, dismissal, and unchanged fixture bytes.
- A deterministic 300-transition lifecycle fuzzer checks renderer/state agreement, extmark/question identity, cache-only reconciliation, duplicate prevention, and active/pending invariants.
- Live direct Gemini priority-inference smoke plus a live restricted OMP/OpenAI OAuth compatibility smoke.
- Neovim configuration load, formatter, diagnostics, and `:checkhealth` must finish cleanly.
- No visible Neovim window or screenshot automation unless the user explicitly approves it.
