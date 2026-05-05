# Phase 3: AgentCore Deploy + Web Widget + Public Demo URL - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-05
**Phase:** 03-AgentCore Deploy + Web Widget + Public Demo URL
**Areas discussed:** IaC flavor for AgentCore (DEP-04), Widget hosting (WID-01 / DEM-01), Widget UX polish level, Abuse prevention + cost cap (DEM-02 / DEM-03)

---

## Gray-area selection (multi-select)

| Option | Description | Selected |
|--------|-------------|----------|
| IaC flavor for AgentCore | DEP-04 fallback decision: TF + CLI vs TF + CDK vs pure TF | ✓ |
| Widget hosting | GitHub Pages vs S3+CloudFront vs serve from agent | ✓ |
| Widget UX polish level | Minimal vs Apple-Store-light vs full-instructor-theme | ✓ |
| Abuse prevention + cost cap | Concurrency / per-IP / banner cap value / circuit-breaker timing | ✓ |

**User's choice:** all four areas selected.
**Notes:** User exercised every gray area — no skips. Carry-forward decisions from Phase 1+2 (transport WSS, region default, multi-arch container, IAM zero-wildcards) were not re-litigated.

---

## Area 1 — IaC flavor for AgentCore (DEP-04)

### Q1.1 — Fallback flavor if Terraform 6.27 lacks native AgentCore resource

| Option | Description | Selected |
|--------|-------------|----------|
| TF + AWS CLI shell-out | TF for KB/IAM/CloudWatch/ECR; AgentCore via `aws bedrock-agentcore-control` CLI in bin script. Paste-friendly FCJ pattern. Trade: weaker idempotency, no TF state for AgentCore. | |
| TF + AWS CDK (Python) | TF for KB/IAM/CloudWatch/ECR; AgentCore as CDK Python stack invoked by `cdk deploy`. Programmatic + idempotent. Trade: 2 IaC tools to teach, extra Preparation chapter for CDK install + bootstrap. | ✓ |
| Pure Terraform, accept risk | Assume TF 6.27 is sufficient; if not, replan. Trade: Phase 3 delay risk if gap exists. | |

**User's choice:** TF + AWS CDK (Python).
**Rationale captured:** Programmatic + idempotent wins despite the two-tool teaching surface; CDK is AWS-native and the right pro-engineering pattern for AgentCore-specific resources.

### Q1.2 — Deploy lifecycle for code updates

| Option | Description | Selected |
|--------|-------------|----------|
| 3-step: build → push → cdk deploy | `bin/build-push.sh` (multi-arch buildx + ECR push, tag = git sha), then `cdk deploy hera-agentcore`. Each step has 1 clear job; debug easier. | ✓ |
| 1-command wrapper: `bin/deploy.sh` | Single bash script orchestrates build/push/cdk. Hides intermediate steps; debug requires reading the script. | |
| CDK does it all (DockerImageAsset) | CDK auto-builds + pushes container; `cdk deploy` is the only command. Trade: loses control over multi-arch buildx flags Phase 2 spent debugging. | |

**User's choice:** 3-step explicit sequence.
**Rationale captured:** Each paste-block surfaces its own exit code; matches Phase 2's "no defensive try/except" + root-cause-debugging discipline.

### Q1.3 — Terraform vs CDK ownership boundary

| Option | Description | Selected |
|--------|-------------|----------|
| TF: everything except AgentCore resource | TF owns KB + ECR + AgentCore exec IAM role + KB-policy attachment + CloudWatch log group + widget hosting. CDK owns one stack with only the AgentCore Runtime resource, reading TF outputs. | ✓ |
| TF: KB + ECR. CDK: AgentCore + IAM exec role | CDK owns both AgentCore resource and its IAM exec role. Trade: IAM lives in 2 places (Phase 1+2 IAM in TF, Phase 3 IAM in CDK — inconsistency). | |
| CDK: all new Phase 3 infra (ECR + IAM + AgentCore + log group) | TF stays Phase 1+2 only; CDK owns all of Phase 3. Trade: cleanup splits across `cdk destroy` + `terraform destroy` for resources that simple TF could have managed uniformly. | |

**User's choice:** TF owns everything except AgentCore resource.
**Rationale captured:** Keeps IAM consistent with Phase 1+2 pattern; CDK only owns what TF can't (AgentCore resource itself); clean cleanup ordering.

---

## Area 2 — Widget hosting (WID-01 / DEM-01)

### Q2.1 — Widget HTML/JS hosting choice

| Option | Description | Selected |
|--------|-------------|----------|
| GitHub Pages | Reuse existing `.github/workflows/` Hugo deploy. Free, HTTPS-included. Trade: cross-origin (GH Pages domain vs AgentCore endpoint) requires CORS; no custom-domain ACM. | |
| S3 + CloudFront | AWS-native: S3 + CloudFront + ACM cert. Workshop teaches "static-site on AWS" as part of the deliverable. Trade: 2 extra TF modules (s3_widget, cloudfront), still has CORS. | ✓ |
| Serve from agent container (FastAPI StaticFiles) | One URL for widget + WSS, no CORS. Trade: AgentCore HTTP path forwarding for non-`/ping`/`/ws` routes is unverified; couples web concerns into agent container. | |

**User's choice:** S3 + CloudFront.
**Rationale captured:** Workshop teaches AWS-native static-site as a deliverable lesson; tightly aligned with "pure-AWS" PROJECT.md mandate.

### Q2.2 — How widget knows the AgentCore WSS URL

| Option | Description | Selected |
|--------|-------------|----------|
| Build-time injection (sed-replace) | `bin/deploy-widget.sh` reads `terraform output -raw agentcore_wss_url`, sed-replaces `__AGENTCORE_WSS_URL__` placeholder in `frontend/app.js` before `aws s3 sync`. Simplest. | ✓ |
| Runtime fetch /config.json | Widget GETs `config.json` from same CloudFront origin before connecting WS. Trade: extra round-trip, error path for missing config. | |
| URL query string (?wss=...) | Widget reads `URLSearchParams.get('wss')`. Trade: instructor must paste the WSS into URL — user-hostile. | |

**User's choice:** build-time injection.
**Rationale captured:** Zero runtime config-fetch logic; fits FCJ paste-pattern; sed-replace works because frontend has no bundler/sourcemaps.

---

## Area 3 — Widget UX polish level

### Q3.1 — Polish target for public demo + workshop final state

| Option | Description | Selected |
|--------|-------------|----------|
| Minimal (keep debug-grade) | Only fix WID-06 error states + WID-05 transcript text events; no branding. | |
| Apple-Store light branding | Logo + neutral background, 5 distinct record-button states, color-coded transcript (User blue / Agent grey), human-readable WID-06 error messages. No modal, no FAQ, no waveform. | ✓ |
| Full instructor demo theme | Above + banner cost cap + onboarding modal + FAQ inline + waveform visualizer. Trade: scope creep risk, longer Phase 3. | |

**User's choice:** Apple-Store light branding.
**Rationale captured:** Hits the public-demo bar without scope creep; debug-grade was insufficient for "click-and-talk" feel for non-developers.

### Q3.2 — Run `/gsd-ui-phase 3` after this discussion?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — generate UI-SPEC.md design contract | High-quality UI-SPEC: 5 button states, error message copy, transcript styling, banner placement, color palette, accessibility notes. Planner + executor use as contract. | ✓ |
| No — let planner heuristics decide in PLAN.md | Save the workflow step; accept potentially shallower polish. | |

**User's choice:** yes, run `/gsd-ui-phase 3` next.
**Rationale captured:** ROADMAP explicitly flags Phase 3 for `/gsd-ui-phase` — proper design contract avoids planner guessing on visual specifics.

---

## Area 4 — Abuse prevention + cost cap (DEM-02, DEM-03)

### Q4.1 — Daily cost cap value (banner copy DEM-03)

| Option | Description | Selected |
|--------|-------------|----------|
| $5/day | Aligns with OBS-03 default + PROJECT.md ("billing alarm $5/ngày cho v1"). Conservative. | ✓ |
| $10/day | 2x for busier demo days. | |
| $2/day strict | Tighter cap; sufficient for proving voice loop only. | |
| Per-instructor TF variable, default $5 | Configurable but adds sed-replace complexity for the banner copy. | |

**User's choice:** $5/day.
**Rationale captured:** Single source of truth across PROJECT.md / OBS-03 / Phase 3 banner; hardcoded keeps Phase 3 simple.

### Q4.2 — Day-1 throttling on AgentCore Runtime

| Option | Description | Selected |
|--------|-------------|----------|
| Conservative: max 2 concurrent, no per-IP | Instructor + 1 viewer ceiling. Bounded blast radius if URL leaks. Sonic 8-min cap = natural max session length. | ✓ |
| Moderate: 5 concurrent + per-IP 1 session | Allows ~5 simultaneous workshop testers. Trade: higher cost ceiling on alarm misfire. | |
| AgentCore default, no custom limits | Rely entirely on Phase 4 billing alarm to stop runaway cost. Trade: no static rail in Phase 3. | |

**User's choice:** conservative — 2 concurrent, no per-IP.
**Rationale captured:** Instructor-demo scope; abuse risk bounded; Phase 4 will layer billing alarm + Lambda circuit-breaker on top.

---

## Claude's Discretion

The user did not actively defer any specific question to Claude during the discussion. The CONTEXT.md captures Claude's-discretion items (CDK Python project layout, image tag scheme details, ECR lifecycle policy, CloudFront cache TTLs, exact AgentCore concurrency knob name, TF→CDK output bridge mechanism) — these remain planner/researcher territory because they depend on what AgentCore actually exposes, not on user opinion.

## Deferred Ideas

- Custom domain + ACM cert for CloudFront → v2 (default `*.cloudfront.net` accepted)
- WebRTC transport for AgentCore endpoint → v2 (Pipecat WSS locked Phase 2 D-19)
- Pipecat client SDK + RTVI in browser → v2 (vanilla AudioWorklet proven)
- Modal onboarding / FAQ inline / waveform visualizer → potential v2 polish
- Cost-circuit-breaker Lambda → Phase 4 OBS-05
- CloudWatch dashboards / billing alarm → Phase 4 OBS-01..03
- `cleanup-verify.sh` script → Phase 4 success criterion #4
- Per-instructor cost-cap config (parameterised) → rejected for v1; edit + redeploy if needed
- GitHub Pages widget host → rejected in favor of S3+CloudFront (D-26 teaching surface)
