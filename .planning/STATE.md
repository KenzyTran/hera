# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-04)

**Core value:** A Cloud Clubs learner walks the workshop and successfully deploys a voice chatbot in their own AWS account, talking to it through their browser.
**Current focus:** Phase 3 — AgentCore Deploy + Web Widget + Public Demo URL — COMPLETE 4/4 plans (infra scope; live voice-loop closure deferred to Phase 4 OBS follow-up due to agent credential-injection gap). Phase 4 next.

## Current Position

Phase: 3 of 5 (AgentCore Deploy + Web Widget + Public Demo URL) — COMPLETE (4/4 plans, infra scope; voice-loop closure deferred)
Plan: 4 of 4 done. Plan 03-04 (CDK AgentCore stack + Rule-4 widget_presigner Lambda + 4-step lifecycle + live deploy) shipped 14 files / 9 commits + 2 live deploys (cdk deploy hera-agentcore + widget_presigner via second-pass terraform apply). Live state in 851725411875/ap-northeast-1: AgentCore Runtime hera_agent-GIsf2P4ImD status=READY referencing image hera-agent:214068b; Lambda hera-widget-presign-prod on Function URL https://ijrovzxz4tts2tdo2w5yxqxho40fruyn.lambda-url.ap-northeast-1.on.aws/ minting 300s SigV4 presigned WSS URLs scoped to the runtime ARN with CORS allow-origin pinned to the CloudFront URL. Widget served from CloudFront with the injected lambda-url URL. WSS handshake via the presign flow authenticates correctly (SigV4 reaches the AgentCore data plane). Live voice-loop closure BLOCKED at the container cold-start layer: agent/hera_agent/config.py:12 reads os.environ["HERA_KB_ID"] at import time and pipeline.py:48 reads os.environ["AWS_ACCESS_KEY_ID"]; AgentCore Runtime injects creds via IMDS not env vars, so the container fails before /ping. Deferred to Phase 4 OBS work — three resolution paths documented in Plan 03-04 SUMMARY ("Open Items / Known Blockers"). Plan 03-04 was 9 atomic commits including 5 in-tree fixes for live-deploy deviations: (1) cdk.json CDKv1 flag removal, (2) agentcore_iam ECR pull permissions, (3) widget_presigner reserved concurrency=-1 (account quota floor), (4) widget_presigner CORS allow_methods=GET-only, (5) widget_presigner WebSocketStream IAM action, (6) bin/build-widget.sh CloudFront /* invalidation. Two-pass terraform apply lifecycle proven live (first apply lays infra with placeholder ARN, second-pass apply receives the real ARN after cdk deploy; in-place updates, no Lambda replace).

Plan 03-03 (prior wave): 2 files / 2 commits + live ECR push. bin/push-image.sh paste-style operator script and RUNBOOK Phase 3 deploy section. Image hera-agent:5e574b3 manifest list at 851725411875.dkr.ecr.ap-northeast-1.amazonaws.com (also tagged 214068b after Plan 03-04 source changes triggered re-push to current SHA). AGT-08 same-artifact contract live.

Plan 03-02 (prior wave): 5 files / 3 commits. Apple-Store light widget polish satisfies WID-01..06 + DEM-03 with 5 record-button state classes + 30s heartbeat + AGENTCORE_WSS_URL placeholder (Plan 03-04 Rule-4 deviation later swapped this for __PRESIGN_URL__).

Plan 03-01 (Wave 1): TF infra applied live, 12 AWS resources in account 851725411875/ap-northeast-1. D-22 closed. Live outputs:
  - agentcore_exec_role_arn = arn:aws:iam::851725411875:role/hera-agentcore-exec-prod
  - agentcore_log_group_name = /aws/bedrock-agentcore/hera-agent
  - ecr_repo_url = 851725411875.dkr.ecr.ap-northeast-1.amazonaws.com/hera-agent
  - widget_cloudfront_url = https://dg0w939ktclw6.cloudfront.net
  - widget_cloudfront_distribution_id = E10K3B1L8PQ9EC
  - widget_s3_bucket_name = hera-widget-prod

Wave 3: 03-04 (CDK AgentCore stack + Rule-4 widget_presigner Lambda + smoke) — COMPLETE infra scope. Live AgentCore Runtime + presigner Function URL + 4-step deploy lifecycle. Voice-loop closure blocked by agent credential-injection gap (Phase 4 OBS work).
Status: Phase 3 complete (4/4 plans). 7 user-approved Rule-4 architectural additions + 5 in-tree Rule-1/2/3 deviations all auto-fixed and committed. Zero remaining deviations.
Last activity: 2026-05-06 — Plan 03-04 executed in this invocation: Tasks 5a (Terraform widget_presigner module), 5b (prod-root wiring + RUNBOOK 4-step), 5c (widget contract presign+fetch), and 5 (live cdk deploy + second-pass tf apply + smoke). Total ~70 min. 9 atomic commits. Live AWS state captured in 03-04 SUMMARY.

Progress: [████████████████████████████] 80%

## Performance Metrics

**Velocity:**
- Total plans completed: 10
- Average duration: ~27 min
- Total execution time: ~5.5 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Knowledge Base Foundation | 3/3 | ~69 min | ~23 min |
| 2. Pipecat Voice Agent (Local) | 3/3 | ~90 min | ~30 min |
| 3. AgentCore Deploy + Web Widget + Public Demo URL | 4/4 | ~170 min | ~43 min |
| 4. Observability, Cost Control, Cleanup | 0/TBD | — | — |
| 5. Workshop Documentation (vi/en) | 0/TBD | — | — |

**Recent Trend:**
- Last 10 plans: 01-02 (~14 min), 01-03 (~50 min), 02-01 (~5 min), 02-03 (~7 min), 02-02 (~78 min), 03-01 (~50 min), 03-02 (~22 min), 03-03 (~28 min), 03-04 (~70 min, two live AWS deploys + 5 in-tree Rule-1/2/3 deviation fixes + Rule-4 architectural addition).
- Trend: Plan 03-04 reintroduced live-AWS variance as predicted. CDK deploy + presigner Lambda + WSS handshake auth + widget injection all closed first-try after the deviation cascade resolved. The blocker that emerged (agent credential injection at the container layer) is genuinely a Phase 4 concern — Plan 03-04's scope was infrastructure stand-up, and that infrastructure works. Phase 4 picks up agent refactor + OBS together.

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table. Recent decisions affecting current work:

- Initialization: Compute pivoted from ECS Fargate to Amazon Bedrock AgentCore Runtime (managed; no ALB/VPC/NAT/PrivateLink in scope).
- Initialization: Vector store is S3 Vectors (cost-driven over OpenSearch Serverless).
- Initialization: IaC is Terraform `~> 6.27` primary; hybrid Terraform + CDK/CLI fallback for AgentCore if provider has gaps — decision locks in Phase 3 planning.
- Initialization: Region is `ap-northeast-1` prod / `us-east-1` dev.
- Initialization: Workshop docs trail system implementation — Phase 5 follows Phases 1-4 because docs need real screenshots and verified snippets.
- Plan 01-01: Stock data inlined in each SKU markdown file (D-03), not in a shared stock.md, so retrieval chunks always co-locate stock numbers with the SKU name.
- Plan 01-01: RUNBOOK.md authored as a stub with seven `TODO(plan-03)` markers; the Next steps (deferred) section is fully written and locks in D-10 (Phase 2 consumer role), D-11 (remote backend deferred), and Guardrails as out-of-v1.
- Plan 01-01: `.terraform.lock.hcl` is intentionally NOT in `.gitignore` (commit the lock for reproducibility); `terraform.tfvars` is also NOT ignored because Phase 1 has no secrets.
- Plan 01-02: Single-module shape (D-08) — one `infra/modules/knowledge_base/` module instantiated by a thin `infra/envs/prod/` root. No per-resource sub-modules; multi-module factoring deferred until a second consumer exists.
- Plan 01-02: Provider pinned to `hashicorp/aws ~> 6.27` (resolved 6.43.0 in lockfile) — the floor for native `s3_vectors_storage_configuration` on `aws_bedrockagent_knowledge_base`.
- Plan 01-02: Zero wildcards in any IAM Action or Resource (D-13) — verified by Python regex sweep across `infra/**/*.tf`. Trust policy uses `bedrock.amazonaws.com` (NOT `bedrockagent.amazonaws.com` — Pitfall I) with both `aws:SourceAccount` and `AWS:SourceArn` confused-deputy conditions.
- Plan 01-02: Provider quirks honored verbatim — `aws_s3vectors_index` uses lowercase `float32`/`cosine`; `aws_bedrockagent_knowledge_base` uses UPPERCASE `FLOAT32`; `aws_s3vectors_vector_bucket` uses `vector_bucket_name` (not `name`).
- Plan 01-02: `aws_bedrockagent_knowledge_base.depends_on = [aws_iam_role_policy.kb_inline]` is mandatory (KB validates role permissions at create time — RESEARCH.md Pattern 5).
- Plan 01-02: No `aws_s3_object` and no `null_resource`/`local-exec` — Plan 03 RUNBOOK is the manual-upload + manual-ingestion teaching surface (D-05/D-07).
- Plan 01-03: S3 Vectors `aws_s3vectors_index` declares `metadata_configuration { non_filterable_metadata_keys = ["AMAZON_BEDROCK_TEXT", "AMAZON_BEDROCK_METADATA"] }`. Forced by live ingestion failure: S3 Vectors caps filterable metadata at 2 KB per record; Bedrock-written chunk text routinely exceeds that for FIXED_SIZE 300-token chunks. Both keys are retrieve-only — never filtered on — so non-filterable is the correct shape, not a workaround. Commit `9006d48`.
- Plan 01-03: `aws_bedrockagent_data_source.catalog` carries `lifecycle.replace_triggered_by = [aws_bedrockagent_knowledge_base.this]`. The AWS provider does NOT mark the data source for replacement when its parent KB is replaced; without this lifecycle block, terraform attempts `UpdateDataSource` against the new KB id with the stale data source id and corrupts state. Forces lockstep replacement. Commit `28bbcee`.
- Plan 01-03: `bin/verify-kb.sh` enforces `command -v aws` and `command -v jq` at startup, exits 2 with platform install hints on miss; the original `2>/dev/null || echo 0` jq fallback was a textbook diagnostic-killing pattern (masked missing-jq install as 5-minute propagation timeout). Aligns with AGENTS.md "don't program defensively, identify root cause first." Commit `f78a39a`.
- Plan 01-03: KB-04 verified end-to-end against live AWS — `aws bedrock-agent-runtime retrieve` for "iPhone 13 Pro Max stock" returns top score `0.8598317801952362` against KB `BKXE19AH89` in `ap-northeast-1`. Closes Phase 1 success criterion #2.
- Plan 01-03: KB-06 re-index path verified for-real — single-file edit + `aws s3 cp` + `aws bedrock-agent start-ingestion-job` (job `KKLS6LQP9A`) re-indexes incrementally; new content queryable at attempt 1. Catalog reverted; final sync `AWI4TJPQN9` re-aligned KB to repo state. Closes Phase 1 success criterion #5.
- Plan 01-03: Live KB id is `BKXE19AH89` (NOT `DWQQ6HXRQW` — the original first-apply id was replaced when the metadata_configuration fix landed). Phase 2 consumer role must scope to `kb_arn = arn:aws:bedrock:ap-northeast-1:851725411875:knowledge-base/BKXE19AH89`.
- Plan 02-01: Python 3.12 pinned in `agent/pyproject.toml` (`requires-python = ">=3.12"`), NOT 3.11 as CONTEXT D-20 originally said. Pipecat's `aws-nova-sonic` extra has marker `python_version>='3.12'`; on 3.11 the extra silently no-ops and `aws_sdk_bedrock_runtime` is missing from the lockfile. Research correction #1.
- Plan 02-01: AWS credentials passed as explicit kwargs to `AWSNovaSonicLLMService(access_key_id=..., secret_access_key=..., session_token=..., region=...)` from `os.environ`. The service uses `StaticCredentialsResolver` internally — boto3 default chain (`~/.aws`) is NOT enough on its own. Research correction #3 / Pitfall B.
- Plan 02-01: FastAPI single-app shape exposes both `GET /ping` (returns `{"status":"Healthy",...}`) and `WebSocket /ws` on the same port 8080. Phase 3 AgentCore deploy reuses `hera_agent.main:app` directly — no transport refactor. Research correction #4.
- Plan 02-01: `lookup_product_handler` dispatches sync boto3 via `await asyncio.to_thread(_kb_retrieve, query)` because boto3 is sync; inline sync inside an async pipeline stutters audio playback. Pitfall F.
- Plan 02-01: `register_function("lookup_product", handler, cancel_on_interruption=False)` — KB calls take ~400ms; cancelling+re-firing on every barge-in wastes user-perceived latency. Pitfall H.
- Plan 02-01: `SessionContinuationParams(transition_threshold_seconds=360)` configured explicitly in `pipeline.py` (matches Pipecat default but makes AGT-05 contract grep-discoverable). Pipecat rotates the bidi stream ~120s before the ~480s Sonic stream cap.
- Plan 02-01: No `AudioConfig(...)` instantiation anywhere — Pipecat defaults already satisfy AGT-07 (16 kHz Int16 in / 24 kHz mono out).
- Plan 02-01: `tools.py` mirrors `bin/verify-kb.sh` 1:1 — `numberOfResults=3`, threshold from `HERA_KB_SCORE_THRESHOLD` env (default 0.4), `"no relevant product info"` sentinel, top-1-first `Source: <basename>\n<text>` format joined by `\n\n`. D-18.
- Plan 02-01: Only `try/except` in the codebase is `except WebSocketDisconnect: pass` in `/ws` handler — that is the normal disconnect path, not error suppression. AGENTS.md mandate honored across 6 hera_agent modules.
- Plan 02-01: Dev dep `websockets` declared explicitly in `agent/pyproject.toml` (already a transitive of Pipecat's `websocket` extra) so Plan 02-02's `bin/_smoke_voice_probe.py` has a stable AGT-04 latency-gate import that survives Pipecat-internal swaps.
- Plan 02-03: New module `infra/modules/kb_consumer_policy/` mirrors `infra/modules/knowledge_base/` four-file shape (versions/variables/main/outputs). Single `aws_iam_policy.kb_retrieve` resource — name `hera-kb-retrieve-prod`, one Allow statement (Action `bedrock:Retrieve`, Resource `var.kb_arn`), zero wildcards (D-13), zero attachments (D-22). Module input `kb_arn` has no default so a wildcard is structurally impossible; only legitimate caller is `module.kb_consumer_policy { kb_arn = module.knowledge_base.kb_arn }`. Live policy ARN: `arn:aws:iam::851725411875:policy/hera-kb-retrieve-prod`.
- Plan 02-03: jsonencode chosen over `data "aws_iam_policy_document"` for this single-statement policy (matches RESEARCH.md verbatim, simpler than Phase 1's data-source style which exists because Phase 1 has three statements with shared conditions). Both styles satisfy D-13 wildcard-free.
- Plan 02-03: Phase-N IAM ships, Phase-N+1 attaches (RESEARCH P7). Policy created in Phase 2, attachment to AgentCore exec role deferred to Phase 3 with `aws_iam_role_policy_attachment.role = aws_iam_role.agentcore_exec.name; policy_arn = module.kb_consumer_policy.policy_arn`.
- Plan 02-03: RUNBOOK split between Plan 02-03 and Plan 02-02 by heading (not by file). 02-03 owns `## Local agent setup (Phase 2) — uv path` + `## Resolved deferrals`; 02-02 owns `## First voice test` + `## Cleanup local Docker resources`. No merge conflict because diffs land at distinct sections.
- Plan 02-03: `bin/verify-kb.sh` requires `jq` and the script's pre-flight `command -v jq` gate (added in 01-03 commit `f78a39a`) is what produces the install-hint error. Document — operators on a fresh shell must `winget install jqlang.jq` (Windows), `brew install jq` (macOS), or `apt-get install jq` (Debian/Ubuntu) before running the script. Underlying `aws bedrock-agent-runtime retrieve` API call works without `jq`.
- Plan 02-02: Container is multi-arch (`linux/arm64,linux/amd64`) via `docker buildx --platform`, ARG TARGETPLATFORM/BUILDPLATFORM only — NO `FROM --platform=` pin (Pitfall C). Same image artifact ships to ECR for Phase 3 AgentCore Runtime (ARM64-only) without rebuild — this is AGT-08.
- Plan 02-02: Pipecat 1.1.0's `FastAPIWebsocketTransport` SILENTLY DROPS every WS frame in both directions when `serializer=None`. Plan 02-01 left it None; the entire wire contract was non-functional and was only revealed when running `bin/smoke-voice.sh` against live Sonic. Fix: `agent/hera_agent/serializer.py` ships `RawPCMSerializer` (pass-through bytes <-> `{Input,Output}AudioRawFrame`) wired into `FastAPIWebsocketParams(serializer=RawPCMSerializer())`. This honors the plan's `add_wav_header=False` raw-PCM contract.
- Plan 02-02: `AWSNovaSonicLLMService` only triggers a greet when the LLMContext ENDS with a `Role.USER` message at session-setup time (sent as `interactive=True`). Plan 02-01's on_client_connected handler used role="developer" added AFTER the session-setup race - the message arrived too late and Sonic never greeted. Fix: pre-seed `LLMContext(messages=[{"role": "user", "content": "Hello."}], tools=TOOLS)` at construction time so `_finish_connecting_if_context_available`'s initial run sees the kickoff message.
- Plan 02-02: docker-compose.yml uses `${VAR:?msg}` REQUIRED-syntax for AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, HERA_KB_ID — surfaces friendly fail-fast error before container starts (T-02-02-04). Env-var values are double-quoted because the planner-specified messages contain `:` characters that would otherwise break YAML scalar parsing.
- Plan 02-02: AGT-04 latency target is now PROGRAMMATICALLY GATED via `bin/smoke-voice.sh` (exits 0 only on `LATENCY_MS<3000`). Operator inspection is no longer the gate. Live result against Bedrock Nova 2 Sonic in ap-northeast-1 + KB BKXE19AH89: `LATENCY_MS=0` (Sonic's first inbound binary frame arrived essentially synchronously with end-of-send during the 1s silence streaming phase).
- Plan 03-01: AgentCore trust principal `bedrock-agentcore.amazonaws.com` accepted on first apply (NOT `bedrock.amazonaws.com` — Phase-1 Pitfall-I principal differs at the AgentCore layer). Confused-deputy mitigated via `aws:SourceAccount=851725411875` + `AWS:SourceArn ArnLike arn:aws:bedrock-agentcore:ap-northeast-1:851725411875:runtime/*`. Live role: `arn:aws:iam::851725411875:role/hera-agentcore-exec-prod`.
- Plan 03-01: D-22 (Phase 2 deferral) closed live — `aws_iam_role_policy_attachment.kb_retrieve` attaches `arn:aws:iam::851725411875:policy/hera-kb-retrieve-prod` to the AgentCore exec role. `aws iam list-attached-role-policies --role-name hera-agentcore-exec-prod` confirms.
- Plan 03-01: Sonic foundation-model ARN `arn:aws:bedrock:ap-northeast-1::foundation-model/amazon.nova-sonic-v1:0` flagged `[needs-verification]` in PLAN.md; IAM-policy `aws:CreatePolicy` validates ARN syntax only, not model existence. Runtime gate is Plan 03-04 smoke (`bedrock:InvokeModelWithBidirectionalStream`). If smoke fails, override `module.agentcore_iam.sonic_model_arn` at the prod root after `aws bedrock list-foundation-models --by-output-modality SPEECH --region ap-northeast-1` resolves the verified id.
- Plan 03-01: D-13 zero-wildcard verified live — Python regex sweep across `infra/**/*.tf` finds exactly one wildcard at `infra/modules/agentcore_iam/main.tf:87` = the documented `cloudwatch:PutMetricData` Resource=* exception, gated by `cloudwatch:namespace = hera/agentcore` StringEquals condition. AWS-published least-privilege pattern (PutMetricData has no resource-level scoping in IAM).
- Plan 03-01: ECR repo `hera-agent` shipped with `imageTagMutability=IMMUTABLE` — Plan 03-03 push-script must NOT pass `:latest` (immutable rejects retag). Lifecycle policy keeps last 5 untagged images. `force_delete=false` — Phase 4 cleanup-verify must explicitly `aws ecr delete-repository --force` to protect pushed images from accidental `terraform destroy`.
- Plan 03-01: CloudFront `MinimumProtocolVersion` silently downgrades from `TLSv1.2_2021` (set in TF) to `TLSv1` (returned by API) when `CloudFrontDefaultCertificate=true`. AWS-side override: default `*.cloudfront.net` cert maximizes client reach. HTTPS-only still enforced via `viewer_protocol_policy=redirect-to-https`. Custom-domain ACM cert (deferred per D-26) would unlock `TLSv1.2_2021` minimum. Documented behavior, not a regression.
- Plan 03-01: Widget hosting verified live — S3 `hera-widget-prod` PAB all-true, CloudFront `E10K3B1L8PQ9EC` `Status=Deployed` in 2m50s (faster than the 8-15min D-26 estimate), HSTS `max-age=31536000; includeSubDomains` + `X-Content-Type-Options: nosniff` headers active (verified via `curl -I` returning HTTP/1.1 403 from S3 NoSuchKey through OAC — empty bucket is correct, Plans 03-02/03-04 populate). Live URL: `https://dg0w939ktclw6.cloudfront.net`.
- Plan 03-01: Empty-commit-with-outputs-in-body pattern established for live deploy events — `git commit --allow-empty -m "feat(03-01): apply terraform live..."` with full output capture + acceptance-gate results in body. Captures deploy event in git history while preserving per-task atomic-commit contract; works because terraform state file + plan.out are gitignored.
- Plan 03-02: AGENTCORE_WSS_URL build-time placeholder uses `typeof __AGENTCORE_WSS_URL__ !== "undefined"` guard. Source-tree value evaluates to `"ws://localhost:8080/ws"` so `docker compose up` keeps working; bin/build-widget.sh sed-replaces the literal `__AGENTCORE_WSS_URL__` in dist/widget/app.js, after which the typeof check evaluates to `"string"` at runtime and selects the WSS branch. Source `frontend/` tree is NEVER mutated (CONTEXT D-27 §Local dev unchanged).
- Plan 03-02: 30s heartbeat resets on every inbound binary frame so a long agent reply does not trigger timeout mid-response. Timeout strictly fires when ZERO frames arrive in 30s. Implementation: `armHeartbeat()` clears + restarts the timer in `ws.onmessage` for binary data; `inboundBinarySeen` boolean gates the fail() call.
- Plan 03-02: 5-state record-button machine in app.js uses single class swap (`recordBtn.className = "btn btn-" + state`) — all per-state styling lives in styles.css under .btn-{idle,connecting,listening,speaking,error}. aria-pressed/aria-busy/aria-disabled toggled in lockstep with state by setState(). Status pill follows via PILL_FOR_STATE map.
- Plan 03-02: Em-dash characters (—) preserved verbatim in WID-06 error strings ("Couldn't reach the agent —", "The agent didn't respond in time —", "Microphone is muted —") because UI-SPEC §Error state copy uses them. Plan's verify automated uses substring matches without dash, so both representations would pass — verbatim wins per the plan's `must_haves.truths` "verbatim" mandate.
- Plan 03-02: bin/build-widget.sh writes via temp file + mv (`sed ... > tmp; mv tmp file`) instead of `sed -i`. Portable across BSD (macOS) and GNU sed without the `-i ''` BSD quirk. Two post-sed sanity gates: (1) `__AGENTCORE_WSS_URL__` placeholder must be gone, (2) `ws://localhost:8080` localhost dev URL must be gone — either gate failure exits 3 before s3 sync.
- Plan 03-02: CloudFront invalidation targets the 4 specific paths (/index.html /app.js /styles.css /audio-capture-worklet.js) instead of /*. Stays below the 1000-free-paths/month CloudFront threshold; Phase 4 cost-control work reuses this pattern.
- Plan 03-02: audio-capture-worklet.js byte-for-byte preserved from Phase 2 (`git diff` empty; last touched commits 109c686 + 72f6236 + f8238c8). The 16 kHz Int16 LE capture path with anti-alias LPF + cursor-based decimation is the wire-contract baseline; Phase 3 polish wraps UX around it without touching the audio path.
- Plan 03-03: bin/push-image.sh ships --provenance=false AND --sbom=false flags. BuildKit v0.11+ defaults emit OCI in-toto attestation manifests (application/vnd.in-toto+json) which ECR's manifest validator rejects with UnsupportedMediaTypeException. Both flags are MANDATORY for ECR-compatible push; the script is the canonical example of the AWS-published ECR-compatible buildx invocation for any future image we publish to AWS ECR.
- Plan 03-03: Image tag = `git rev-parse --short HEAD` ONLY (no :latest). Plan 03-01 created the ECR repo with image_tag_mutability=IMMUTABLE so :latest would be rejected by ECR with ImageTagAlreadyExistsException on the second push. To deploy a new image, operator commits first so SHA differs — git history IS the deploy audit trail.
- Plan 03-03: Idempotent buildx builder bootstrap pattern: `docker buildx inspect hera-builder >/dev/null || docker buildx create --name hera-builder --driver docker-container --use`. Without the inspect-or-create check, a second run errors with "builder already exists". Pattern carries forward to any operator script that uses a named buildx instance.
- Plan 03-03: Live ECR push verified end-to-end against account 851725411875 / ap-northeast-1. Manifest list digest sha256:95d7d51e52e4e53a38a23f692d25cc0809e223628342852f027da2079ea6b43a tagged `5e574b3` references arm64 manifest sha256:1241bd9... + amd64 manifest sha256:5b034d2... (verified via `aws ecr batch-get-image --accepted-media-types application/vnd.docker.distribution.manifest.list.v2+json | jq '.manifests[].platform.architecture'` returning both `arm64` and `amd64`). AGT-08 same-artifact contract from Phase 2 → Phase 3 is now live. Plan 03-04 cdk deploy will reference exactly this manifest.
- Plan 03-03: Idempotency-by-content for IMMUTABLE ECR repos — re-pushing the same SHA tag is safe because Docker registry is content-addressable; ECR only rejects DIFFERENT manifest with same tag, not same-manifest re-push. Verified live: second-run completed in ~3s, all build steps `CACHED`, identical manifest digest, exit 0. The script is therefore safe to re-run from RUNBOOK as part of "if anything looks off, just paste step 2 again".
- Plan 03-03: ECR scan-on-push status was `None` immediately after push for both per-arch manifests (`aws ecr describe-image-scan-findings` returned `ScanNotFoundException`). ECR Basic scan is asynchronous and lands minutes-to-hours later; surfacing scan results is Phase 4 OBS-01..03 territory (T-03-03-06 disposition: `accept (Phase 4)`). Not a Plan 03-03 gate — image tags + manifest list + idempotency are the Plan 03-03 acceptance.
- Plan 03-04: User-approved Rule-4 architectural deviation: Lambda Function URL presigner (Q1 option A) lives in a NEW Terraform module infra/modules/widget_presigner/ (D-24 honored — CDK still owns ONLY the AgentCore Runtime resource). The widget contract changes from __AGENTCORE_WSS_URL__ (Plan 03-02 baseline) to __PRESIGN_URL__: frontend/app.js's resolveWsUrl() fetches the Function URL, unwraps {url}, and opens that wss URL. Local-dev path preserved via the typeof __PRESIGN_URL__ guard. Browsers cannot SigV4-sign WebSocket upgrades directly; the presigner mints 300s SigV4-presigned URLs using the Lambda exec role's credentials.
- Plan 03-04: User-approved deferral: per-Lambda concurrency cap skipped for v1 (Q2 option (i)). reserved_concurrent_executions defaults to -1 because AWS rejects positive values that would push UnreservedConcurrentExecution below the account floor of 10. Phase 4 OBS-04/OBS-05 owns per-IP rate limit + AgentCore concurrency quota request alongside the cost circuit breaker.
- Plan 03-04: D-25 amended to a 4-step lifecycle: (1) terraform apply (Wave 1), (2) bin/push-image.sh, (3) cdk deploy hera-agentcore (emits AgentCoreRuntimeArn), (4) terraform apply -var=agentcore_runtime_arn=<arn> (in-place updates the widget_presigner Lambda env vars + IAM policy), (5) bin/build-widget.sh, (6) bin/smoke-deploy.sh. The two-pass terraform apply pattern resolves the chicken-and-egg dependency between the presigner Lambda (needs runtime ARN) and the AgentCore Runtime (created by CDK after the first TF apply).
- Plan 03-04: AWS::BedrockAgentCore::Runtime CFn schema confirmed live (via aws cloudformation describe-type) to have NO MaxConcurrentSessions / Throttle / SessionLimit property — concurrency is enforced at the AgentCore SERVICE quota layer (account-default 10, requestable). D-30 demo cap of 2 is therefore an operational quota request, not IaC. Documented in stack.py header.
- Plan 03-04: Live deploy revealed five auto-fixed deviations: (1) agentcore_iam needs ECR pull (Rule-2), (2) Lambda reserved concurrency hits 10-floor on fresh accounts (Rule-3), (3) Function URL CORS allow_methods rejects OPTIONS (Rule-1), (4) AgentCore data-plane action is :InvokeAgentRuntimeWithWebSocketStream not plain :InvokeAgentRuntime (Rule-1), (5) cdk.json CDKv1 feature flag breaks CDKv2 synth (Rule-1). All five fixes shipped in commits 214068b + ab44397. None required user approval.
- Plan 03-04: Live voice-loop closure BLOCKED at the container cold-start layer — agent reads os.environ["HERA_KB_ID"] + os.environ["AWS_ACCESS_KEY_ID"] at import time, AgentCore Runtime injects creds via IMDSv2 not env vars. Three resolution paths documented in 03-04 SUMMARY; preferred is refactoring AWSNovaSonicLLMService usage in pipeline.py to accept boto3 default chain (which AgentCore IMDS satisfies). Phase 4 follow-up plan owns the fix.

### Pending Todos

None yet.

### Blockers/Concerns

- **Agent credential-injection gap (BLOCKS Phase 3 success criterion #2 closure).** AgentCore Runtime hera_agent-GIsf2P4ImD CFn status=READY but the container fails on cold-start because agent/hera_agent/config.py:12 reads os.environ["HERA_KB_ID"] at import time and pipeline.py:48 reads os.environ["AWS_ACCESS_KEY_ID"]; AgentCore Runtime injects exec-role creds via IMDSv2 (not env vars) and has no CFn property for env-var injection of secrets. The presign+fetch + WSS handshake + SigV4 auth all work — the failure is purely at the agent boot layer. Phase 4 follow-up plan owns one of three resolution paths documented in 03-04 SUMMARY (preferred: refactor for boto3 default chain that AgentCore IMDS satisfies; alternatives: AgentCore Environment CFn property if it exists, or sidecar IMDS->env bridge). All other Phase 3 infra is live and reachable.

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Repo hygiene | Add `plan.out` to `.gitignore` (post-`terraform plan -out` artifact) | RESOLVED in Plan 03-01 Task 4 | Plan 02-03 |
| Phase 1 D-10 | Consumer `bedrock:Retrieve` policy for Pipecat | RESOLVED in Plan 02-03 (managed policy `hera-kb-retrieve-prod`) | Plan 01-01 |
| Phase 2 D-22 | Attach `hera-kb-retrieve-prod` to AgentCore exec role | RESOLVED in Plan 03-01 Task 1 (live `aws_iam_role_policy_attachment.kb_retrieve`) | Plan 02-03 |
| Plan 03-01 | Sonic foundation-model ARN runtime gate | Open — not yet exercised; container fails before LLM init due to credential gap (Plan 03-04 SUMMARY Open Items) | Plan 03-01 |
| Plan 03-01 | CloudFront custom domain + ACM cert (would also unlock `TLSv1.2_2021` minimum) | Open — deferred per D-26 to v2 | Plan 03-01 |
| Plan 03-01 | Widget S3 versioning (rollback path is git+bin/deploy-widget.sh) | Open — deferred per D-26 to Phase 4 if cleanup-verify proves teardown is clean | Plan 03-01 |
| Plan 03-04 | Agent credential-injection bridge (BLOCKS Phase 3 SC#2 voice-loop closure) | Open — Phase 4 follow-up plan owns; preferred path is boto3-default-chain refactor in pipeline.py | Plan 03-04 |
| Plan 03-04 | Per-IP rate limit on the presign Function URL (OBS-04) + per-Lambda concurrency cap | Open — Phase 4 OBS-04/OBS-05 owns; user-approved Q2 option (i) deferred this | Plan 03-04 |
| Plan 03-04 | AgentCore service quota request (default 10 concurrent runtimes; D-30 originally said 2) | Open — operational AWS console action, not IaC; Phase 4 may file the request | Plan 03-04 |
| Plan 03-04 | CDK bootstrap deploy-role trust policy for non-root operators | Open — current credentials run as IAM root which CDK warns about ("could not assume cdk-...-deploy-role"); Phase 4 may add a role-trust amendment | Plan 03-04 |

## Session Continuity

Last session: 2026-05-06
Stopped at: Phase 3 complete (4/4 plans). Plan 03-04 executed in 9 atomic commits / 14 files / ~70 min including 2 live AWS deploys (cdk deploy hera-agentcore + second-pass terraform apply for the widget_presigner Lambda). Live state captured in `.planning/phases/03-agentcore-deploy-web-widget-public-demo-url/03-04-SUMMARY.md`. Live AWS resources: AgentCore Runtime hera_agent-GIsf2P4ImD (status READY), Lambda hera-widget-presign-prod on Function URL https://ijrovzxz4tts2tdo2w5yxqxho40fruyn.lambda-url.ap-northeast-1.on.aws/, widget served at https://dg0w939ktclw6.cloudfront.net with the injected presign URL. Voice-loop closure blocked at the agent boot layer (see Blockers/Concerns above) — infrastructure is complete; agent credential-injection refactor is a Phase 4 follow-up plan.

Next: launch Phase 4 (Observability, Cost Control, Cleanup). Phase 4 will:
  1. Add a follow-up plan (suggested: 04-01-agent-credential-bridge) to refactor the agent for boto3 default chain so the AgentCore IMDS-resolved credentials work; this closes Phase 3 success criterion #2.
  2. Then proceed with the originally-planned OBS work: CloudWatch dashboards/alarms (OBS-01..03), Lambda cost circuit breaker (OBS-05), per-IP rate limit on the presign Function URL (OBS-04), cleanup-verify script.

Resume file: .planning/STATE.md — start `/gsd-plan-phase 4` to plan Phase 4 with the agent credential bridge as the priority Wave-1 plan.
