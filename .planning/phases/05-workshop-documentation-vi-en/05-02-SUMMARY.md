---
phase: 05-workshop-documentation-vi-en
plan: 02
subsystem: workshop-docs
tags: [docs, hugo, vi, en, bilingual, phase-2-prep, phase-3-knowledge-base, phase-3-pipecat-local]
requires:
  - 05-01-PLAN.md (DOC-12 parity gate live; bin/check-i18n-parity.sh wired into .github/workflows/deploy.yml; vi=6 en=6 baseline post-Plan-05-01)
provides:
  - DOC-02 (Phần 2 Preparation vi+en — AWS account + model access + tool installs + credentials + cost expectation)
  - DOC-03 (Phần 3.1 Knowledge Base sub-page vi+en — terraform apply + ingestion + verify + re-index)
  - DOC-04 (Phần 3.2 Pipecat Local sub-page vi+en — pyproject + main + prompts + tools + pipeline + uv path + compose path + smoke gate)
  - 5 of 8 D-51 pitfall callouts placed (#1 8-min cap, #2 16/24kHz audio, #3 model access, #6 tool-use schema, #8 KB sync delay)
  - D-44 #1 image markdown reference inserted in Phần 2 (vi+en) with static/images/2-preparation/.gitkeep placeholder
affects:
  - content/vi/2-preparation/_index.md (replaced FCJ template body)
  - content/en/2-preparation/_index.md (replaced FCJ template body)
  - content/vi/3-hands-on/3.1-knowledge-base/_index.md (new sub-page)
  - content/en/3-hands-on/3.1-knowledge-base/_index.md (new sub-page)
  - content/vi/3-hands-on/3.2-pipecat-local/_index.md (new sub-page)
  - content/en/3-hands-on/3.2-pipecat-local/_index.md (new sub-page)
  - static/images/2-preparation/.gitkeep (new placeholder for D-44 #1 hero PNG)
tech-stack:
  added: []
  patterns:
    - sub-page-front-matter (D-40 — title + date + weight only; no chapter:true, no pre)
    - source-footer-italic (D-42 + D-43 — `*Source: <repo-relative-path> — Phase X Plan XX-XX*` directly under fenced code block)
    - notice-callout-at-trigger (D-51 — Pattern S4; `{{% notice warning %}}` for "watch out", `{{% notice info %}}` for "FYI")
    - same-commit-vi-en (D-49 — Pattern S1; one chapter = one atomic commit with both language files)
    - cost-language-anchored-to-D54 (per checker WARNING 2 — `~$2-5 USD per 2-hour session` ballpark plus post-launch-update notice; no literal `~$X-Y` placeholder strings)
key-files:
  created:
    - static/images/2-preparation/.gitkeep
    - content/vi/3-hands-on/3.1-knowledge-base/_index.md
    - content/en/3-hands-on/3.1-knowledge-base/_index.md
    - content/vi/3-hands-on/3.2-pipecat-local/_index.md
    - content/en/3-hands-on/3.2-pipecat-local/_index.md
  modified:
    - content/vi/2-preparation/_index.md
    - content/en/2-preparation/_index.md
decisions:
  - Cost language uses D-54 anchored `~$2-5 USD per 2-hour session` ballpark + post-launch-update `{{% notice info %}}` callout instead of literal `~$X-Y` placeholders (per checker WARNING 2). Per-service breakdown table not shipped in 05-02; it lands in 05-04 Phần 5 Summary.
  - Snippet attribution uses repo-relative path with no SHA and no GitHub permalink (D-43). 6 chapter files contain a combined 19 unique source-footer paths (audited via `grep -h '^\*Source:' ... | sort -u | wc -l`).
  - Phần 2 image markdown reference shipped without the underlying PNG; `.gitkeep` placeholder ensures the path resolves at directory level. Operator captures `console-bedrock-model-access.png` post-content (tracked via 04-HUMAN-UAT screenshot sweep + Plan 05-03 screenshot inventory).
  - Phần 3.2 callout #6 (tool-use schema) lives at the tools.py section choke point; #1 (8-min cap) at SessionContinuationParams; #2 (audio sample rate) immediately after #1 because both relate to pipeline audio behaviour.
  - Long Python source quotes (main.py 38 lines, prompts.py 12 lines, tools.py 49 lines, pipeline.py ~25 lines) are reproduced near-verbatim from frozen Phase 1-2 source. The `pipeline.py` quote is the only one abbreviated (FastAPIWebsocketTransport instantiation collapsed into `transport = FastAPIWebsocketTransport(...)` and pipeline assembly elided via `# ... pipeline assembly ...`) because the full body is 50+ lines and the relevant teaching surface is `build_llm()` + `register_function()`. Abbreviation marker `# ...` is the standard Python source-elision convention.
metrics:
  duration_minutes: 25
  date_completed: 2026-05-07
  files_created: 5
  files_modified: 2
  tasks_completed: 4
  commits: 4
---

# Phase 5 Plan 02: Phần 2 Preparation + Phần 3.1 Knowledge Base + Phần 3.2 Pipecat Local Summary

3 chapters published bilingual (vi+en in same atomic commit per D-49) covering the AWS account → first hands-on arc that gets a learner from a fresh AWS account to a locally-running voice loop with KB-backed tool calls. Zero new AWS deploys; all snippets reproduced verbatim from frozen Phase 1-2 source with D-42 italic Source footers.

## Execution overview

Plan was fully autonomous, 4 atomic commits, no checkpoints, no deviations. Each chapter committed individually with both language files; the .gitkeep landed in its own commit before Phần 2 so the markdown image reference resolved against an existing directory at the moment Phần 2 was rendered.

## Tasks completed

| Task | Name | Commit | Files |
| ---- | ---- | ------ | ----- |
| 0 | Create static/images/2-preparation/.gitkeep | ffbc109 | static/images/2-preparation/.gitkeep |
| 1 | Author Phần 2 Preparation single-page in vi+en (DOC-02 + D-51 #3 + D-44 #1 image) | 3101e73 | content/{vi,en}/2-preparation/_index.md |
| 2 | Author Phần 3.1 Knowledge Base sub-page in vi+en (DOC-03 + D-51 #8) | f488751 | content/{vi,en}/3-hands-on/3.1-knowledge-base/_index.md |
| 3 | Author Phần 3.2 Pipecat Local sub-page in vi+en (DOC-04 + D-51 #1, #2, #6) | a06b993 | content/{vi,en}/3-hands-on/3.2-pipecat-local/_index.md |

## File-count parity at end of plan

- vi=8 (`content/vi/_index.md` + 5 chapter `_index.md` + 2 new sub-pages 3.1-knowledge-base/_index.md + 3.2-pipecat-local/_index.md)
- en=8 (mirror)
- 16 total `_index.md` files
- `bash bin/check-i18n-parity.sh` exits 0 — file-count parity assertion + bidirectional slug-tree parity assertion both pass.

## D-51 pitfall callouts placed (5 of 8 total in this plan)

| ID | Chapter | Section heading | Style |
| -- | ------- | --------------- | ----- |
| #3 model access (per-region per-model) | Phần 2 Preparation | Bật Bedrock model access (per-region, per-model) / Enable Bedrock model access | `notice warning` |
| #8 KB sync delay | Phần 3.1 Knowledge Base | Bước 3: Verify Retrieve API / Step 3: Verify Retrieve API | `notice warning` |
| #6 tool-use schema strictness | Phần 3.2 Pipecat Local | tools.py: lookup_product calls KB Retrieve | `notice warning` |
| #1 8-min Sonic stream cap | Phần 3.2 Pipecat Local | pipeline.py: AWSNovaSonicLLMService + SessionContinuationParams | `notice warning` |
| #2 audio sample rate 16kHz / 24kHz | Phần 3.2 Pipecat Local | pipeline.py: AWSNovaSonicLLMService + SessionContinuationParams (info follow-on) | `notice info` |

Combined notice count across 6 modified/created files: 12 (`grep -h '{{% notice'` returns 12 — 6 per language).

Remaining 3 D-51 callouts placed elsewhere or pending:
- #7 bilingual parity — placed in Plan 05-01 Phần 1 Introduction
- #4 HTTPS-for-mic — pending Plan 05-03 Phần 3.4 Web Widget
- #5 billing alarm cleanup — pending Plan 05-04 Phần 4 Cleanup

## Image markdown references inserted (D-44 #1)

`![Bedrock Console — Model Access for Nova 2 Sonic + Titan v2 (ap-northeast-1)](/images/2-preparation/console-bedrock-model-access.png)` shipped in both `content/vi/2-preparation/_index.md` and `content/en/2-preparation/_index.md` (alt-text intentionally English in both languages — the model name + region label is identifier text, not prose). Underlying PNG capture deferred to operator screenshot sweep (tracked alongside 04-HUMAN-UAT items + Plan 05-03 image inventory).

`static/images/2-preparation/.gitkeep` ships as an empty file so the directory resolves before the PNG arrives. Hugo renders the `<img>` element with alt-text only until the PNG lands — no broken-image error in the build.

## Source-footer inventory (D-42 / D-43)

Per-chapter footer counts:
- Phần 2 Preparation (vi): 8
- Phần 2 Preparation (en): 8
- Phần 3.1 KB (vi): 6
- Phần 3.1 KB (en): 6
- Phần 3.2 Pipecat Local (vi): 13
- Phần 3.2 Pipecat Local (en): 13

19 unique footer source paths cited (vi + en deduped):

- `RUNBOOK.md (Pre-flight) — Phase 1 Plan 01-01`
- `RUNBOOK.md (Pre-flight) — Phase 1 Plan 01-03`
- `RUNBOOK.md (First deploy) — Phase 1 Plan 01-02`
- `RUNBOOK.md (First sync) — Phase 1 Plan 01-03`
- `RUNBOOK.md (Re-index) — Phase 1 Plan 01-03`
- `RUNBOOK.md (Cleanup local Docker resources) — Phase 2 Plan 02-02`
- `bin/verify-kb.sh — Phase 1 Plan 01-03`
- `bin/run-agent-local.sh — Phase 2 Plan 02-01`
- `bin/smoke-voice.sh — Phase 2 Plan 02-02`
- `agent/pyproject.toml — Phase 2 Plan 02-01`
- `agent/Dockerfile — Phase 2 Plan 02-02`
- `agent/hera_agent/main.py — Phase 2 Plan 02-01 (POST /invocations added Phase 4 Plan 04-01)`
- `agent/hera_agent/prompts.py — Phase 2 Plan 02-01`
- `agent/hera_agent/tools.py — Phase 2 Plan 02-01`
- `agent/hera_agent/pipeline.py — Phase 2 Plan 02-01`
- `agent/ — Phase 2 Plans 02-01 + 02-02` (project-tree explanation)
- `catalog/ — Phase 1 Plan 01-01`
- `docker-compose.yml — Phase 2 Plan 02-02`
- `frontend/audio-capture-worklet.js — Phase 2 Plan 02-02`

All paths repo-relative — no SHA, no GitHub permalink (D-43). Operator can `grep '^\*Source:'` content tree to audit drift; if any path moves, re-paste with new path.

## Source-quoting deviations

Only one elision worth flagging: **`pipeline.py` quote in Phần 3.2** is abbreviated rather than verbatim. Two collapses:

1. `FastAPIWebsocketTransport(...)` instantiation: 12-line params block elided to `transport = FastAPIWebsocketTransport(...)`. Reason: full body distracts from the teaching surface (LLM construction + tool registration + session continuation); transport configuration is the same Plan 02-02 wire contract documented elsewhere.
2. Pipeline assembly: `pipeline = Pipeline([...])` + `task = PipelineTask(...)` + event handlers elided to `# ... pipeline assembly ...`. Reason: `build_llm()` is the load-bearing function the chapter is teaching; pipeline assembly is Pipecat-framework boilerplate that learners cross-reference in `agent/hera_agent/pipeline.py` directly.

Both elisions use the standard Python `...` / `# ...` source-elision convention. The reader can `cat agent/hera_agent/pipeline.py` for the full body — that's the entire reason D-42 mandates the path footer.

The `main.py` quote is line-for-line verbatim except for some inline comments collapsed (the file's BOOT_TIME comment block + WebSocketDisconnect comment block — non-load-bearing prose comments that the chapter explains in surrounding text instead). All other quotes (`pyproject.toml`, `prompts.py`, `tools.py`) are 100% verbatim.

## Cost-language framing (per checker WARNING 2)

Phần 2 Preparation `## Kỳ vọng chi phí` / `## Cost expectations` section:

- Anchored ballpark: `~$2-5 USD ballpark` for a 2-hour session (D-54 anchor).
- Two cost drivers: Bedrock Nova 2 Sonic streaming + AgentCore Runtime session-second.
- Cleanup imperative: chạy Phần 4 ngay sau session; Cost Explorer 24h lag.
- Post-launch-update `{{% notice info %}}` callout pointing to Phần 5 Summary for instructor-pulled real numbers + bookmarking `https://aws.amazon.com/bedrock/pricing/` for live AWS pricing.

Greppable check: `grep -c '~\$X-Y' content/{vi,en}/2-preparation/_index.md content/{vi,en}/3-hands-on/3.1-knowledge-base/_index.md content/{vi,en}/3-hands-on/3.2-pipecat-local/_index.md` returns 0.

## Region default check (D-47)

Every CLI snippet ships with `--region ap-northeast-1` or relies on the env-var default `${AWS_REGION:-ap-northeast-1}`. Every Bedrock model ID + KB id reference cites the live ap-northeast-1 deployment. The single mention of alternative regions in Phần 2 (`us-east-1`, `us-west-2`, `eu-north-1`) is explicitly flagged as a region-override decision the learner makes in `infra/envs/prod/terraform.tfvars` before `terraform apply` — matches the Phần 1 framing from Plan 05-01.

## Verification gates (final tree)

```bash
$ find content/vi -name "_index.md" -type f | wc -l
8
$ find content/en -name "_index.md" -type f | wc -l
8
$ bash bin/check-i18n-parity.sh
check-i18n-parity against content/vi vs content/en
----------------------------------------
OK: file count parity (vi=8, en=8)
OK: vi/en slug tree parity
----------------------------------------
check-i18n-parity: 2/2 parity assertions passed
OK: vi/en _index.md tree parity (DOC-12)
$ grep -P '[\x{1F300}-\x{1F9FF}]' content/vi content/en static
(no output — emoji-free)
$ git diff --submodule themes/hugo-theme-learn
(no output — submodule untouched)
```

## Deviations from Plan

None — plan executed exactly as written. No Rule 1/2/3 auto-fixes; no Rule 4 architectural escalations; no authentication gates; no checkpoints; no scope reductions.

## Authentication gates

None. Docs-only plan with zero AWS calls.

## Threat Flags

No new threat surface introduced. The 4 STRIDE entries from the plan's `<threat_model>` are all `accept` or `mitigate` per existing operator discipline:

- T-05-02-01 (snippets quoting `agent/hera_agent/config.py`): accepted — file uses `os.environ.get(...)` with defaults, no real credentials in source. Chapter shows env-var NAMES learner sets in their own `.env`.
- T-05-02-02 (notice shortcode body tampering): accepted — `unsafe = true` is pre-existing config.toml setting; callout bodies are authored markdown, not user input.
- T-05-02-03 (source-footer drift): mitigate — D-42 + D-43 specify repo-relative path; operator can `grep '^\*Source:'` to audit. Phase 5 is last v1 phase so source is frozen; drift risk bounded.
- T-05-02-04 (Bedrock Console screenshot leaking account ID): accepted — operator follows D-44 capture guidance; redaction is operator responsibility.

## Self-Check: PASSED

Created files exist:
- `static/images/2-preparation/.gitkeep` — FOUND
- `content/vi/2-preparation/_index.md` — FOUND (159 lines)
- `content/en/2-preparation/_index.md` — FOUND (159 lines)
- `content/vi/3-hands-on/3.1-knowledge-base/_index.md` — FOUND (143 lines)
- `content/en/3-hands-on/3.1-knowledge-base/_index.md` — FOUND (143 lines)
- `content/vi/3-hands-on/3.2-pipecat-local/_index.md` — FOUND (321 lines)
- `content/en/3-hands-on/3.2-pipecat-local/_index.md` — FOUND (321 lines)

Commits exist:
- ffbc109 — FOUND
- 3101e73 — FOUND
- f488751 — FOUND
- a06b993 — FOUND

Acceptance gates:
- All min_lines targets met (Phần 2 vi/en >= 100; 3.1 vi/en >= 80; 3.2 vi/en >= 100).
- Source-footer counts: Phần 2 8/side; 3.1 6/side; 3.2 13/side. Combined >= 10 unique paths cited (achieved 19 unique).
- Notice counts: 1 warning + 1 info in Phần 2 each side; 1 warning in 3.1 each side; 2 warning + 1 info in 3.2 each side. Combined 12 (matches plan verification step 4).
- D-44 #1 image reference present in Phần 2 vi+en (1 occurrence each, 2 total — matches plan verification step 5).
- Em-dash present in 3.2 vi (24 occurrences).
- No emojis (combined grep returns 0 across 6 modified files).
- No `~$X-Y` placeholder strings (combined grep returns 0).
- Submodule `themes/hugo-theme-learn/` untouched (`git diff --submodule` empty).
- `static/images/2-preparation/.gitkeep` exists.
- `bash bin/check-i18n-parity.sh` exits 0.

All success criteria met.
