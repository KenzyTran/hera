# Twilio Bridge — Phase 6 PARTIAL Archive

**Archived:** 2026-05-16
**Phase context:** v2.0 Milestone — Phase 6 (Twilio Bridge + Phone Number + Cleanup)
**Status:** Architectural defect surfaced; module preserved as historical reference. NOT in active terraform state.

> WARNING: Do NOT run `terraform init` from inside this directory. This module's `versions.tf` is preserved verbatim for git-blame fidelity; running init would attempt to lock providers against an obsolete architecture. The active root `infra/envs/prod/main.tf` no longer references this module.

## What this was

Phase 6 shipped a Twilio Media Streams bridge: a Python FastAPI container deployed to AWS App Runner that terminated inbound Twilio Media Streams WebSocket connections, validated `X-Twilio-Signature` HMAC, resampled μ-law 8 kHz audio to Int16 16 kHz (and back), and forwarded audio bidirectionally to the existing Hera AgentCore Runtime via SigV4-signed WSS. Goal: a learner dials a Twilio US DID and talks to the same Hera Apple Store assistant the v1 web widget reaches.

Resources in this module: 1 App Runner service, 1 App Runner auto-scaling configuration, 1 ECR repository (immutable), 2 IAM roles (App Runner instance role + access role) with confused-deputy conditions, 2 inline policies (zero IAM wildcards per D-13), 1 CloudWatch log group, 1 Secrets Manager-sourced Twilio Auth Token wiring.

## Why it was archived (D-56 finding — link below)

Live deploy of Plan 06-04 (2026-05-16) succeeded at the deploy layer — multi-arch container pushed, App Runner service reached RUNNING, HTTPS `/ping` returned 200 OK in 0.69 s. However, synthetic WebSocket upgrade probes against the App Runner edge returned HTTP 403 regardless of path or headers. Root cause confirmed via AWS documentation: **AWS App Runner does not support inbound WebSocket connections** (outbound WS works, inbound is unsupported on the App Runner edge envoy). Since the entire purpose of this bridge was to receive Media Streams WS upgrades FROM Twilio, the compute target was structurally incompatible with the use case.

Full finding text: `.planning/phases/06-twilio-bridge-phone-number-cleanup/06-04-SUMMARY.md` (the canonical D-56 architectural defect record).

Decision (2026-05-16): user pivoted v2.0 entirely to Amazon Connect (native AWS, no third-party telephony). Phase 6.1 supersedes Phase 6 (see `.planning/phases/06.1-native-aws-voice-channel-amazon-connect/`).

## What was correct (preserved verbatim — usable for any future Twilio re-pivot)

- **`src/resample.py`** — μ-law 8 kHz <-> Int16 16 kHz audio resampling using `audioop-lts==0.2.2`. Offline-verified via `tests/test_resample.py` (round-trip energy preservation, sample-rate exactness). The resample math is correct and reusable on any compute target.
- **`src/main.py`** — FastAPI `/ping` + `/twilio` WS endpoints; signature validation runs BEFORE `accept()` per Twilio security guidance (D-67). The handler shape is correct; only the compute target was wrong.
- **`src/bridge.py`** — per-call coroutine that opens an upstream SigV4-signed WSS connection to AgentCore Runtime, threads ratecv resampler state per direction, pumps audio bidirectionally between Twilio Media Streams and the agent. Logic is correct.
- **`Dockerfile`** — multi-arch (linux/arm64,linux/amd64) buildx-compatible; mirrors `agent/Dockerfile`. Reusable on ECS Fargate / Lambda / EC2 unchanged.
- **IaC IAM shape** — `iam.tf` ships 2 roles with `aws:SourceAccount` confused-deputy conditions and zero wildcards. The IAM model carries forward to any compute-target re-pivot.

Offline test suite passed 10/10 at archive time (commit `c6ac618` and earlier per `06-04-SUMMARY.md`).

## What was wrong (do not repeat)

The compute-target choice was wrong, not the application code. AWS App Runner with `min_size=0` (D-56's original "scale-to-zero" reasoning) suffered two distinct failures: (1) App Runner ASC rejects `min_size=0` at the API layer (the resource was patched to `min_size=1` mid-deploy in commit `e2a0a96`); (2) the App Runner edge envoy returned HTTP 403 on every inbound WebSocket upgrade attempt regardless of path or headers — a documented platform limitation that no configuration can work around.

Secondary planning errors documented in `06-04-SUMMARY.md`: `ECR_PUBLIC` placeholder image-type plus `authentication_configuration.access_role_arn` is not an accepted combo (App Runner CreateService rejects), so the two-pass chicken-and-egg apply pattern from Phase 3 was not directly portable here.

## Re-pivot pointers (if v3+ ever revisits Twilio)

Recommended compute target if Twilio Media Streams ingress is ever revisited: **ECS Fargate behind a Network Load Balancer (NLB)**. Rationale: NLB supports inbound WS upgrades natively at the listener layer, Fargate provides the long-running container surface the bridge needs, and Fargate's spot-eligibility keeps the demo-budget impact low. Secondary option: EC2 behind an Application Load Balancer (ALB) — ALB also supports inbound WS but adds VPC/subnet complexity that Fargate-with-NLB avoids.

Files in this archive directly portable to that re-pivot (no changes required beyond compute-target wiring): `src/`, `tests/`, `pyproject.toml`, `uv.lock`, `Dockerfile`. Files that require rewrite (compute-target-specific): `main.tf`, `outputs.tf`, `variables.tf` (App Runner-specific resource declarations).

v2.0 milestone closed with Phase 6.1 (Amazon Connect, native AWS — no third-party telephony). Twilio path remains preserved here for future reference only.
