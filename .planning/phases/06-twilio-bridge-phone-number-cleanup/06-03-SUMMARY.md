---
phase: 06-twilio-bridge-phone-number-cleanup
plan: 03
status: complete
completed: 2026-05-07
mode: inline-orchestrator
---

# Plan 06-03 Summary — File-side Operator Artifacts

## Objective

Ship the file-side operator artifacts that Plan 06-04 will consume during the live deploy + dial-in smoke + REQ flips:
- `bin/push-bridge-image.sh` — multi-arch buildx push of the hera-twilio-bridge container to the Phase 6 ECR
- `bin/cleanup-verify-twilio.sh` — read-only AWS + Twilio resource verification (9 checks)
- `RUNBOOK.md` — Phase 6 paste-blocks (operator setup + 2-pass terraform apply + TwiML Bin wiring + dial-in smoke with stopwatch latency protocol + cleanup quy trinh)

Zero live AWS work; zero edits to v1 files (D-64).

## Execution mode

This plan was executed **inline by the orchestrator** rather than via a `gsd-executor` subagent, after the Wave 2 subagent dispatch hit a Write-tool permission gate that could not be lifted from inside the agent. The dangling worktree was cleaned up; the orchestrator then performed all three tasks atomically. Mode confirmed by user (option A — "inline execution").

## Tasks

### Task 1 — `bin/push-bridge-image.sh` (commit `002cfed`)

- 94 lines, mirrors `bin/push-image.sh` (Plan 03-03) verbatim with three changes per PATTERNS.md:
  - ECR URL output name: `ecr_repo_url` -> `twilio_bridge_ecr_repository_url`
  - Build context dir: `agent/` -> `infra/modules/twilio_bridge`
  - Final hint: `cdk deploy hera-agentcore` -> `terraform apply -var=twilio_bridge_image_tag=$GIT_SHA ...`
- Pattern S5 flags non-negotiable: `--provenance=false --sbom=false` (ECR rejects OCI in-toto provenance/SBOM manifests)
- Multi-arch: `--platform linux/arm64,linux/amd64`
- Idempotent buildx builder bootstrap (`docker buildx inspect hera-builder || docker buildx create ...`)
- Tool preflight: aws + docker + git + terraform + buildx
- Tag scheme: short git SHA only (IMMUTABLE ECR rejects `:latest`)
- `bash -n` clean
- File made executable
- v1 `bin/push-image.sh` unchanged (D-64)

### Task 2 — `bin/cleanup-verify-twilio.sh` (commit `ed0c55b`)

- 164 lines, mirrors `bin/cleanup-verify.sh` (Plan 04-03) verbatim for preflight/helpers/summary
- Resource list (9 checks):
  1. App Runner service `hera-twilio-bridge-prod` (count=0)
  2. App Runner ASC `hera-twilio-bridge-asc-prod` (count=0)
  3. ECR repo `hera-twilio-bridge` (RepositoryNotFoundException)
  4. IAM role `hera-twilio-bridge-instance-prod` (NoSuchEntity)
  5. IAM role `hera-twilio-bridge-access-prod` (NoSuchEntity)
  6. CW log group `/aws/apprunner/hera-twilio-bridge-prod` (count=0; MSYS_NO_PATHCONV=1 per Pattern S8)
  7. Secrets Manager secret `hera/twilio/auth-token` (ResourceNotFound)
  8. Twilio incoming phone numbers tagged `hera` (count=0 via REST + jq)
  9. Twilio TwiML Bins tagged `hera` (count=0 via REST + jq; 404 treated as OK)
- `GONE_REGEX` extends with `ServiceNotFound|ServiceNotFoundException` for App Runner
- `_check_count_zero` strips whitespace before integer compare (T-06-03-03 mitigation)
- Strict `set -euo pipefail` + 2>&1 capture so transient API errors do not silently count as gone
- Twilio TwiML Bins endpoint 404 path documented (accounts that have never used Bins)
- FAIL hint block lists cleanup quy trinh order issues
- `bash -n` clean
- File made executable
- v1 `bin/cleanup-verify.sh` unchanged (D-64)

### Task 3 — `RUNBOOK.md` Phase 6 section (commit `b0ceb22`)

- 186 lines appended at end of file (existing 763 lines preserved verbatim)
- Heading: `## Phase 6 — Twilio Voice Channel Setup (operator paste-style)` (em-dash + parenthetical, matches Phase 4 convention)
- Section structure (per RESEARCH.md outline):
  1. Pre-flight (tools + Twilio account + funded balance + stopwatch)
  2. Create Twilio account + capture credentials (Account SID + Auth Token)
  3. Step 1.5 — Create Secrets Manager secret for the Auth Token (D-67)
  4. Buy a phone number
  5. First-pass terraform apply (placeholder image — chicken-and-egg per Pattern S10)
  6. Build + push the real bridge image
  7. Second-pass terraform apply (pin real image SHA)
  8. Create TwiML Bin (with `<Connect><Stream>` mandate; explicit DO NOT use `<Start>` warning per Pitfall 1)
  9. Wire voice webhook
  10. Smoke test with stopwatch latency protocol — Phase 6 SC#1
  11. Cost watch
  12. Cleanup quy trinh (Twilio FIRST -> terraform destroy -> Secrets Manager -> verify)
- WARNING-2 stopwatch protocol: PASS/WARN/FAIL gate with explicit thresholds (<=3s / 3-5s / >5s); Audacity fallback for recorded-call sample-count measurement at 8 kHz
- WARNING-5 git-clean preflight: `git diff --quiet && git diff --cached --quiet` BEFORE pinning `BRIDGE_SHA` (avoids tag/SHA desync if operator commits between Step 4 push and Step 5 apply)
- D-59 caveat surfaced in Step 8 audio quality check: `SONIC_OUTPUT_RATE_HZ = 16000` may need flip to 24000 if Sonic's voice sounds chipmunked
- D-64 v1 unchanged check (browser widget + AgentCore concurrency cap=2 interaction)
- Cleanup quy trinh order: release Twilio number FIRST, delete TwiML Bin, terraform destroy, delete Secrets Manager secret, run cleanup-verify-twilio.sh
- All existing Phase 4/5 sections bit-identical (D-64)

## Verification

| Gate | Result |
|------|--------|
| `bash -n bin/push-bridge-image.sh` | exit 0 |
| `bash -n bin/cleanup-verify-twilio.sh` | exit 0 |
| `grep '^## Phase 6 — Twilio Voice Channel Setup' RUNBOOK.md` | line 765 |
| `grep -c '^### Step ' RUNBOOK.md` | 23 (Phase 4 + Phase 5 + Phase 6 combined; >= 9 required) |
| 14 keyword acceptance checks (RUNBOOK) | all ok |
| WARNING-2 stopwatch protocol (`STOP the stopwatch` + `PASS` + `WARN` + `FAIL` + `Audacity`) | ok |
| WARNING-5 git-clean preflight in Step 4 | ok |
| Emoji scan across all 3 artifacts | none |
| `git diff bin/cleanup-verify.sh` (D-64) | empty |
| `git diff bin/push-image.sh` (D-64) | empty |
| Existing RUNBOOK content untouched | ok (`git diff` shows append only) |

## Threat-model dispositions

| Threat ID | Status |
|-----------|--------|
| T-06-03-01 (Twilio Auth Token literal) | mitigate — RUNBOOK Step 1 marks `(NEVER commit)`; Step 1.5 reads from `$TWILIO_AUTH_TOKEN` env, never inline |
| T-06-03-02 (push-bridge-image tag collision) | mitigate — git short SHA + IMMUTABLE ECR + WARNING-5 git-clean preflight |
| T-06-03-03 (cleanup-verify-twilio false PASS) | mitigate — `_check_count_zero` whitespace strip + `_check_gone` multi-error regex + `set -euo pipefail` |
| T-06-03-04 (Twilio REST creds in env) | accept — operator pastes; script does not log; SID is operationally visible |
| T-06-03-05 (RUNBOOK overwrite Phase 4/5) | mitigate — append-only Edit on the unique last line; existing 763 lines bit-identical |

## v1 zero-edit audit (D-64)

`git diff HEAD~3..HEAD -- agent/ cdk/ infra/modules/knowledge_base/ infra/modules/kb_consumer_policy/ infra/modules/agentcore_iam/ infra/modules/ecr/ infra/modules/widget_hosting/ infra/modules/widget_presigner/ infra/modules/observability/ frontend/ bin/cleanup-verify.sh bin/push-image.sh` returns nothing — confirmed.

## Hand-off to Plan 06-04

Plan 06-04 (Wave 3, autonomous=false) will:
- Read this RUNBOOK Phase 6 section verbatim and walk the operator through Steps 1-1.5 (operator paste-flow checkpoint #1: Twilio account creation + Secrets Manager paste + number purchase)
- Run the live two-pass terraform apply + bin/push-bridge-image.sh from Steps 3-5
- Drive the operator dial-in checkpoint (#2) using Step 8's stopwatch latency protocol
- Capture the empty-commit-with-outputs-in-body for the live deploy event
- Flip TWIL-01..04 in REQUIREMENTS.md + ROADMAP.md + STATE.md after smoke pass

All file-side artifacts Plan 06-04 needs are now committed on master.

## Commit graph

```
b0ceb22 docs(06-03): RUNBOOK Phase 6 -- Twilio Voice Channel Setup operator paste-blocks (with stopwatch latency protocol)
ed0c55b feat(06-03): add bin/cleanup-verify-twilio.sh -- read-only AWS + Twilio resource verification
002cfed feat(06-03): add bin/push-bridge-image.sh -- multi-arch buildx push of bridge container to ECR
```

## Self-Check: PASSED
