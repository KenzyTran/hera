---
phase: 04-observability-cost-control-cleanup
plan: 01
subsystem: infra
tags: [agentcore, fastapi, pipecat, ecr, cdk, http-protocol, bedrock]

# Dependency graph
requires:
  - phase: 03-agentcore-deploy-web-widget-public-demo-url
    provides: live AgentCore Runtime hera_agent-GIsf2P4ImD (version=2 from Plan 03-05) + ECR repo + ProtocolConfiguration=HTTP from CDK Plan 03-04 routing inbound to /invocations
provides:
  - "POST /invocations static-envelope route on the FastAPI app (canonical awslabs sample shape — voice loop continues on /ws)"
  - "AgentCore Runtime hera_agent-GIsf2P4ImD updated in place to version=3 with image tag 7e72b66"
  - "RUNBOOK.md `## Phase 4: Protocol-bridge deploy` section (4-step paste-style lifecycle + rollback)"
  - "ROADMAP Phase 3 SC#2 closure marked with evidence (data-plane invoke statusCode=200)"
  - "ROADMAP Phase 4 SC#2/SC#3 wording realigned with locked decisions D-35 + D-36"
affects: [04-02-observability, 04-03-cleanup-verify, phase-5-workshop-docs]

# Tech tracking
tech-stack:
  added: []  # No new libraries — JSONResponse already in fastapi 0.115
  patterns:
    - "AgentCore HTTP protocol contract: POST /invocations returns 200 with static envelope; voice loop on /ws"
    - "In-place CDK redeploy with --context image_tag=<sha> (version=2 -> version=3) — same stack name, same logical IDs"
    - "Empty-commit-with-outputs-in-body for live AWS deploy events (Plan 03-01 pattern carried forward)"

key-files:
  created:
    - ".planning/phases/04-observability-cost-control-cleanup/04-01-SUMMARY.md"
  modified:
    - "agent/hera_agent/main.py"
    - "RUNBOOK.md"
    - ".planning/ROADMAP.md"

key-decisions:
  - "D-31 honored verbatim: /invocations is a static-envelope stub, NOT a Pipecat-pipeline bridge — voice loop stays on /ws (canonical awslabs pattern)"
  - "D-32 honored: local docker-compose dev stays on /ws; AgentCore HTTP path uses /invocations"
  - "D-33 honored: scope = agent/ + RUNBOOK.md only; ZERO CDK source change, ZERO Terraform change"
  - "D-34 honored: SC#2 closure smoke is a single AgentCore data-plane invoke-agent-runtime call returning 200; browser test stays optional"
  - "Demo budget honored: 1 ECR push + 1 cdk deploy + 1 smoke probe = total 3 billable AWS write events; old image hera-agent:5f21e36 retained for rollback"

patterns-established:
  - "Multi-arch image build is slow but reliable: ~13 min wall time on a cold push (387s for `docker buildx build --push` of layers, ~62s per arch for the useradd/chown layer). Future Phase 4 plans should NOT trigger more rebuilds unless code changes."
  - "AWS CLI `bedrock-agentcore invoke-agent-runtime` requires --payload as base64 (not raw JSON) — the response body is downloaded to the path arg, statusCode lives in the meta JSON printed to stdout."

requirements-completed: [DEP-02, DEM-02]

# Metrics
duration: ~50min
completed: 2026-05-06
---

# Phase 4 Plan 01: Agent Protocol-Bridge Summary

**POST /invocations static-envelope route exposed on the live Pipecat FastAPI container; AgentCore data-plane invoke now returns statusCode=200 with `{"agent":"hera-pipecat-sonic","status":"running","model":"amazon.nova-sonic-v1:0"}`. Phase 3 SC#2 closed.**

## Performance

- **Duration:** ~50 min wall (most spent in multi-arch buildx `pushing layers 387s`)
- **Started:** 2026-05-06T19:14:30Z (continuation agent resume; Task 1 was already at 7e72b66)
- **Completed:** 2026-05-06T20:00:00Z
- **Tasks:** 3 (Task 1 from prior agent; Tasks 2-3 here)
- **Files modified:** 3 (`agent/hera_agent/main.py` from Task 1; `RUNBOOK.md` + `.planning/ROADMAP.md` from Task 3)

## Accomplishments

- `POST /invocations` route added to `agent/hera_agent/main.py` returning the canonical awslabs static envelope; `/ping` and `/ws` byte-for-byte preserved (zero Phase 2 regression).
- Multi-arch image rebuilt and pushed to ECR with tag `7e72b66`; manifest list confirms both `linux/arm64` (sha256:198b4c15...) and `linux/amd64` (sha256:1ee6139b...) children. Old tag `5f21e36` retained for rollback (ECR `imageTagMutability=IMMUTABLE`).
- AgentCore Runtime `hera_agent-GIsf2P4ImD` updated in place via `cdk deploy hera-agentcore --context image_tag=7e72b66` — CFn `UPDATE_COMPLETE`, runtime version increments 2 -> 3, status=READY.
- SC#2 closure smoke probe via `aws bedrock-agentcore invoke-agent-runtime` returns statusCode=200; runtimeSessionId=`7e9a4d15-9d3f-4be3-be66-84b5723bf5ec`. Phase 3 SC#2 (live AgentCore data-plane reachability) is **CLOSED**.
- RUNBOOK.md gains a heading-disjoint `## Phase 4: Protocol-bridge deploy` section with the 4-step paste-style lifecycle + rollback path.
- ROADMAP.md Phase 3 row + progress-table row + Phase 4 SC#2/SC#3 D-35/D-36 wording realignment all applied in one commit.

## Route stub diff and rationale

```python
# agent/hera_agent/main.py — added between /ping and /ws (preserves the natural GET, POST, WebSocket order):
from fastapi.responses import JSONResponse  # added to imports

@app.post("/invocations")
async def invocations() -> JSONResponse:
    """AgentCore HTTP data-plane stub. Voice loop runs on /ws (D-31)."""
    return JSONResponse(
        {
            "agent": "hera-pipecat-sonic",
            "status": "running",
            "model": "amazon.nova-sonic-v1:0",
        }
    )
```

Module docstring updated from "Exposes two routes" -> "Exposes three routes" with the `/invocations` line added.

**Rationale (D-31, RESEARCH section A):** The canonical `awslabs/agentcore-samples/.../06-bi-directional-streaming/04-pipecat-sonic-ws` pattern keeps `/invocations` as a status-stub HTTP route. The actual bidi voice loop runs on `/ws`. This is the smallest practical diff that satisfies the AgentCore HTTP protocol contract (set in CDK Plan 03-04 via `ProtocolConfiguration: HTTP`) without forcing a Pipecat-on-HTTP refactor that would conflict with `AWSNovaSonicLLMService`'s WebSocket-only contract. Per AGENTS.md root-cause discipline the handler has no try/except (returns a dict literal — no exceptions to catch); per PITFALL G.1 it returns `JSONResponse({...})` for explicit Content-Type; per PITFALL G.2 no CORS middleware was added (the AgentCore deploy path doesn't need it).

## Task Commits

1. **Task 1: Add POST /invocations route to FastAPI app** — `7e72b66` (feat) — committed by prior executor; verified intact at HEAD on resume (line 38 of `agent/hera_agent/main.py`).
2. **Task 2: Live cdk redeploy + SC#2 closure smoke probe** — `9c5db62` (feat, empty commit with outputs in body) — captures image SHA + ECR digest + Runtime version=3 transition + smoke response body.
3. **Task 3: RUNBOOK Phase 4 section + ROADMAP SC#2 closure + SC#2/SC#3 D-35/D-36 alignment** — `5037f1f` (docs).

_Note: a SUMMARY metadata commit follows this file's creation._

## Live evidence

### Image (ECR)

| Field | Value |
|---|---|
| Tag | `7e72b66` (= git short SHA of feat(04-01) /invocations commit) |
| Repo | `851725411875.dkr.ecr.ap-northeast-1.amazonaws.com/hera-agent` |
| Manifest list digest | `sha256:7ce1f1ceb25774f2af7f074eb6e0ba2d073d6c45f30b685b0e1357a101308b25` |
| arm64 child | `sha256:198b4c15ed2d7d0efac9dfa4401c4053e4c3eac5b0f4e5f0933036b63e192335` |
| amd64 child | `sha256:1ee6139ba52a4a214208c3d1ec7c7c59724c78ceeaff4aa7b167439021c92105` |
| Pushed at | 2026-05-06T19:33:56.815+07:00 |
| Old tag retained | `5f21e36` (Plan 03-05) — ECR `imageTagMutability=IMMUTABLE` |

### AgentCore Runtime version=3

| Field | Value |
|---|---|
| Runtime ARN | `arn:aws:bedrock-agentcore:ap-northeast-1:851725411875:runtime/hera_agent-GIsf2P4ImD` |
| Runtime ID | `hera_agent-GIsf2P4ImD` |
| Status | `READY` |
| Version | `3` (was `2` from Plan 03-05) |
| ContainerUri | `851725411875.dkr.ecr.ap-northeast-1.amazonaws.com/hera-agent:7e72b66` |
| CFn stack | `hera-agentcore` (existing; UPDATE_COMPLETE) |
| Stack ARN | `arn:aws:cloudformation:ap-northeast-1:851725411875:stack/hera-agentcore/0bc06dd0-4914-11f1-9976-061c6ad5cb0b` |
| Deploy wall time | ~46s synth + 19s deploy = ~65s |

### SC#2 closure smoke probe (D-34)

```
aws bedrock-agentcore invoke-agent-runtime \
  --region ap-northeast-1 \
  --agent-runtime-arn "$RUNTIME_ARN" \
  --payload <base64({"prompt":"healthcheck"})> \
  --content-type application/json --accept application/json \
  /tmp/agentcore-response.json
```

Result:

| Field | Value |
|---|---|
| Exit code | `0` |
| `statusCode` | `200` |
| `contentType` | `application/json` |
| `runtimeSessionId` | `7e9a4d15-9d3f-4be3-be66-84b5723bf5ec` |
| Response body | `{"agent":"hera-pipecat-sonic","status":"running","model":"amazon.nova-sonic-v1:0"}` |

This is the SC#2 evidence. The AgentCore data-plane invoke now reaches `POST /invocations` on the live container and returns the static envelope.

## A2 [needs-verification] resolution

The smoke probe ran under the operator's default profile (root credentials Phase 3 also used). `bedrock-agentcore:InvokeAgentRuntime` succeeded with no extra IAM grant. **A2 is NOT a blocker for this plan.** RUNBOOK Phase 4 Step 4 retains the call-out for non-root operators (the IAM identity must have `bedrock-agentcore:InvokeAgentRuntime` on the runtime ARN).

## D-30 concurrency cap=2 status

Still **operational, deferred** — the AWS console service-quota request to lower the AgentCore concurrency cap from default-10 to D-30's 2 is not IaC and is not in this plan's scope. Default cap stays active. Plan 04-02 OBS work does not touch it.

## ROADMAP Phase 3 SC#2 closure

Three ROADMAP edits in one commit (5037f1f):

1. **Phase 3 row (line 17):** appended evidence — `**SC#2 closed by Plan 04-01 (Phase 4 Wave 1) — POST /invocations stub deployed; AgentCore data-plane invoke returns 200.**`
2. **Phase 3 progress-table row (line 157):** flipped status to `Complete (5/5 SC; SC#2 closed by Plan 04-01)`.
3. **Phase 4 SC#2 + SC#3 (lines 109-110):** wording realigned with locked decisions D-35 (no SNS / Lambda hook on billing alarm; `alarm_actions=[]`) and D-36 (no per-IP rate limit on presigner; AgentCore concurrency cap=2 is the gate).

## Decisions Made

None — followed plan as specified. All locked decisions D-31 through D-34 honored verbatim.

## Deviations from Plan

None auto-fixed under Rules 1-3. Two operational realities surfaced during execution that are documented here for transparency but did NOT require code/plan changes:

1. **Docker Desktop daemon was not running on operator workstation when push-image.sh first invoked** — surfaced as `failed to connect to the docker API at npipe:////./pipe/dockerDesktopLinuxEngine`. Resolved automatically by `Start-Process` of Docker Desktop.exe; daemon ready in 6s; push retried successfully. Not a Rule-1/2/3 deviation — environment startup, no code change.

2. **`uv run cdk` failed with "program not found"** — `cdk` is a Node CLI on PATH (`/c/nvm4w/nodejs/cdk`), not a Python entry point in `infra/cdk/.venv`. Plan body uses `uv run cdk deploy ...`; the actual invocation that worked is `cdk deploy ...` directly (cdk.json already specifies `app: "uv run python app.py"` so Python deps still resolve via uv). RUNBOOK.md keeps the plan's `uv run cdk` form to match the plan body verbatim — operators on a fresh workstation should run `cdk deploy` directly if `uv run cdk` errors. Not a Rule-1/2/3 deviation — environmental tool-resolution detail.

3. **AWS CLI `bedrock-agentcore invoke-agent-runtime` requires `--payload` as base64-encoded** — the plan's verbatim CLI sample uses raw JSON `'{"prompt":"healthcheck"}'`; the actual invocation needed `echo -n '...' | base64 -w0` first. The plan's `<interfaces>` smoke probe shape is documented from RESEARCH section A, which predates the latest AWS CLI v2 strict-base64 enforcement. RUNBOOK.md reproduces the plan's verbatim form (operator paste-style); operators will need to base64-encode in practice. Filed as a doc-only follow-up note here. Not a Rule-1/2/3 deviation — CLI surface detail.

**Total deviations:** 0 Rule-1/2/3 fixes; 3 documented operational notes.
**Impact on plan:** Zero. All success criteria met as specified.

## Issues Encountered

- **Multi-arch buildx push wall time:** ~13 min wall (387s `pushing layers` + ~125s `useradd/chown` for both arches + manifest export). Reasonable for cold push of a 517 MB multi-arch image with no buildkit cache hit. Future Phase 4 plans (04-02, 04-03) do NOT rebuild the image, so this cost is not repeated.
- **Docker Desktop not running at start:** auto-resolved (started programmatically; 6s to readiness).

## User Setup Required

None — Task 2 ran under operator credentials already in shell (account 851725411875, region ap-northeast-1). A2 IAM grant was unnecessary for this run (root profile). For non-root operator profiles, RUNBOOK Phase 4 Step 4 documents the `bedrock-agentcore:InvokeAgentRuntime` requirement.

## Next Phase Readiness

- **Phase 3 SC#2 CLOSED** — live AgentCore data-plane invoke returns 200 (proven 2026-05-06T19:36+07:00). ROADMAP reflects.
- **Phase 4 Wave 2 unblocked:**
  - Plan 04-02 (observability dashboard + alarms) can deploy against real traffic from the now-functional /invocations route.
  - Plan 04-03 (cleanup-verify.sh) can target the live AWS state baseline that includes hera-agent:7e72b66 in ECR.
- **Old image hera-agent:5f21e36 retained on ECR** for rollback (`(cd infra/cdk && uv run cdk deploy hera-agentcore --context "image_tag=5f21e36" --require-approval never)`).
- **D-30 AgentCore concurrency cap=2 service-quota request** — still deferred (operational console action, not IaC). Plan 04-02 may add a paste-line in RUNBOOK if the quota code is researcher-confirmed.
- **Sonic foundation-model ARN runtime gate** (carried from Plan 03-01) — NOT exercised by this plan because /invocations does not init Sonic streaming. Will surface for the first time when an actual /ws voice session runs against version=3 from a real browser. Optional browser test in RUNBOOK Phase 4 is the path.

## Self-Check: PASSED

- File existence verified:
  - `agent/hera_agent/main.py` (Task 1 — `POST /invocations` route at line 38)
  - `RUNBOOK.md` (`## Phase 4: Protocol-bridge deploy` heading present exactly once)
  - `.planning/ROADMAP.md` (SC#2 closure note + D-35 + D-36 alignment text all present)
  - `.planning/phases/04-observability-cost-control-cleanup/04-01-SUMMARY.md` (this file)
  - `dist/cdk-outputs.json` (live cdk deploy outputs)
- Commits verified in `git log --oneline --all`: `7e72b66` (Task 1), `9c5db62` (Task 2 live-deploy event), `5037f1f` (Task 3 RUNBOOK+ROADMAP), `4dc62fb` (SUMMARY).
- Live AWS state verified: `aws bedrock-agentcore-control get-agent-runtime --agent-runtime-id hera_agent-GIsf2P4ImD` returns `{"status":"READY","version":"3"}` post-deploy.

---
*Phase: 04-observability-cost-control-cleanup*
*Completed: 2026-05-06*
