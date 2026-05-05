# Phase 1: Knowledge Base Foundation - Context

**Gathered:** 2026-05-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Apple product catalog (3 SKUs: Apple Watch S11, iPhone 13 Pro Max, MacBook Pro M4) is ingested into a Bedrock Knowledge Base backed by S3 Vectors with Titan v2 embeddings, deployed end-to-end with Terraform `~> 6.27` into `ap-northeast-1`, and queryable via `aws bedrock-agent-runtime retrieve` with a least-privilege IAM role. The KB service role is in scope; the `bedrock:Retrieve` consumer role used by the Pipecat agent is deferred to Phase 2. No Pipecat code, no AgentCore, no widget, no observability dashboards — those are later phases.

</domain>

<decisions>
## Implementation Decisions

### Catalog content shape
- **D-01:** Source bucket holds **4 English markdown files**:
  - `apple-watch-s11.md`
  - `iphone-13-pro-max.md`
  - `macbook-pro-m4.md`
  - `store-policy.md` (return policy, store hours, warranty — sidecar so Sonic persona has more than just product Q&A)
- **D-02:** Per-SKU schema (drives chunking quality with 300-token / 20%-overlap fixed-size chunks):
  - `# <SKU full name>`
  - `## Overview` — 1–2 sentences of prose
  - `## Specifications` — bullet list (chip, RAM, storage, display, battery, color options, weight, dimensions)
  - `## Pricing` — list price in USD per configuration
  - `## Stock & Availability` — current stock count + ETA if zero
- **D-03:** Stock data lives **inline** inside each SKU file (not in a shared `stock.md`) so every retrieval chunk that contains a stock number also contains the SKU name — strengthens recall for KB-04's verification query "iPhone 13 Pro Max stock".
- **D-04:** Default fixed-size chunking (300 tokens, 20% overlap). Do NOT use hierarchical chunking with S3 Vectors (Pitfall #8 — metadata cap risk).

### Sync trigger / re-index UX (KB-06)
- **D-05:** **Manual** first-sync workflow. `terraform apply` creates the KB but does NOT auto-trigger ingestion. Learner runs `aws bedrock-agent start-ingestion-job ...` as a separate documented step.
- **D-06:** Re-index after editing a product file uses the **same** command. Bedrock KB detects changed objects and incrementally re-embeds only the diff. Documented in a top-level `RUNBOOK.md` in the repo, surfaced into workshop Phase 5 docs by reference.
- **D-07:** No auto-sync `null_resource` inside Terraform. No wrapper sync script. Keeps state clean of side-effects and teaches the API surface explicitly.

### Terraform module + IAM shape
- **D-08:** **Single module** `modules/knowledge_base/` contains:
  - `aws_s3_bucket` for source markdown (`force_destroy = true`)
  - `aws_s3vectors_vector_bucket`
  - `aws_s3vectors_index` (dimension=1024, distance_metric="cosine", data_type="float32")
  - `aws_bedrockagent_knowledge_base` with `s3_vectors_storage_configuration`
  - `aws_bedrockagent_data_source` pointing at the source bucket
  - KB service IAM role + scoped policy (S3 source read, S3 Vectors read/write, `bedrock:InvokeModel` on Titan v2 ARN, `bedrock:Retrieve` on its own KB ARN as the trust principal)
  - Outputs: `kb_id`, `kb_arn`, `source_bucket_name`, `data_source_id`
- **D-09:** Match REQUIREMENTS.md DEP-03 module path naming: `modules/knowledge_base/` (alias `modules/kb` if needed).
- **D-10:** **Defer** the consumer-side `bedrock:Retrieve` role to Phase 2. Phase 1 only outputs the `kb_arn` so Phase 2 can scope its Pipecat task role policy. Avoids creating "ahead-of-need" IAM that may not match the final shape of the agent.
- **D-11:** Local Terraform state for v1 workshop default. Document remote backend (S3 versioned + DynamoDB lock) as a "next step" in RUNBOOK.md but do NOT bootstrap it in Phase 1. Aligns with STACK.md guidance and avoids chicken-and-egg.
- **D-12:** **Fixed resource names** (e.g., `hera-kb-prod`, `hera-kb-source-prod`, `hera-kb-vectors-prod`). No `random_id` suffix. Recovery path for half-failed apply is `terraform destroy` + re-apply (Pitfall #17), explicitly documented in RUNBOOK.md.
- **D-13:** **Zero IAM wildcards** in Action or Resource. All actions enumerated; resource ARNs scoped to the specific KB / model / bucket. Workshop teaches the right pattern from day one (Pitfall #23).
- **D-14:** Region defaults to `ap-northeast-1` (prod) via Terraform variable, supports override to `us-east-1` for dev (per DEP-06).

### Verification artifact for KB-04
- **D-15:** Ship `bin/verify-kb.sh` in the repo. Behavior:
  - Reads KB id from `terraform output` (or accepts `--kb-id` flag)
  - Calls `aws bedrock-agent-runtime retrieve` with retrievalQuery `iPhone 13 Pro Max stock`
  - Polls every 15s, max 5 minutes (covers Pitfall #9 propagation lag)
  - Exits 0 when `retrievalResults` is non-empty AND top score is above a documented threshold
  - Exits non-zero with a clear human-readable message on timeout / empty / access denied
- **D-16:** Script is reusable in Phase 4 cleanup verification with the assertion inverted (expect access-denied / KB-not-found post-`terraform destroy`).

### Claude's Discretion
- Exact wording of each markdown file's prose (Overview, store policy text)
- Exact stock numbers and pricing values (use plausible 2026 figures)
- Default Terraform variable values beyond region (e.g., name prefix, retention)
- Threshold value for `verify-kb.sh` "score above X" check (start ~0.4, tune empirically)
- File layout details inside `modules/knowledge_base/` (split into `main.tf` / `iam.tf` / `outputs.tf` etc. — pick what reads best)
- Exact CLI flags and output formatting of `verify-kb.sh`

</decisions>

<specifics>
## Specific Ideas

- The existing AWS reference repo `aws-samples/sample-nova-sonic-websocket-agentcore` contains a working `Retrieve`-as-a-tool example for Pipecat — the schema we ingest now should be retrievable through that exact tool path in Phase 2 without reformatting.
- The 8-min Sonic stream cap (Pitfall #1) is irrelevant to Phase 1, but the catalog answers must be SHORT (a few sentences each) so Sonic can finish its TTS within a single 8-min session in Phase 2 — this informs the per-section prose length above.
- "store-policy.md" sidecar is a nod to the Apple Store assistant persona in `raw_content.txt` — the original tutorial demoed return-policy and hours questions, not just product specs.

</specifics>

<canonical_refs>
## Canonical References

**Downstream agents (researcher, planner) MUST read these before planning or implementing.**

### Project-level (locked stack and scope)
- `.planning/PROJECT.md` — locked decisions (Nova 2 Sonic, Pipecat, AgentCore, S3 Vectors, Terraform `~> 6.27`, ap-northeast-1, no NAT/VPC/PrivateLink, no DynamoDB)
- `.planning/REQUIREMENTS.md` — KB-01 through KB-06 (the 6 requirements this phase delivers); see also DEP-03/DEP-05/DEP-06 for IAM and module shape implications
- `.planning/ROADMAP.md` §"Phase 1: Knowledge Base Foundation" — phase goal and 5 success criteria
- `.planning/STATE.md` — current cursor (start of Phase 1, no plans yet)

### Stack and pitfalls (research output, HIGH confidence)
- `.planning/research/STACK.md` — Titan v2 model id `amazon.titan-embed-text-v2:0` at 1024 dim float32 cosine; native `aws_s3vectors_vector_bucket`, `aws_s3vectors_index`, `aws_bedrockagent_knowledge_base` resources in `hashicorp/aws ~> 6.27`; module structure recommendations; default chunking guidance
- `.planning/research/PITFALLS.md` §Pitfall #3 — Bedrock model access enable per-region (preparation step before any apply)
- `.planning/research/PITFALLS.md` §Pitfall #8 — S3 Vectors index dimension immutability (cannot change without destroy/recreate)
- `.planning/research/PITFALLS.md` §Pitfall #9 — KB sync → retrieve propagation lag (2–3 minutes); informs `verify-kb.sh` design
- `.planning/research/PITFALLS.md` §Pitfall #17 — Terraform half-apply recovery (informs the "no random suffix, document destroy+re-apply recovery" decision)
- `.planning/research/PITFALLS.md` §Pitfall #20 — cleanup completeness (informs `force_destroy = true` decision)
- `.planning/research/PITFALLS.md` §Pitfall #23 — no IAM wildcards
- `.planning/research/ARCHITECTURE.md` §"Phase 1 — Knowledge Base end-to-end" and §"[B] Knowledge Base" block diagram

### AWS authoritative docs (planner should consult)
- AWS docs — Using S3 Vectors with Bedrock Knowledge Bases (limitations, dim/metric requirements): https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-vectors-bedrock-kb.html
- AWS docs — Bedrock KB sync (start-ingestion-job): https://docs.aws.amazon.com/bedrock/latest/userguide/kb-data-source-sync-ingest.html
- AWS docs — Bedrock KB IAM examples: https://docs.aws.amazon.com/bedrock/latest/userguide/knowledge-base-setup.html
- Terraform Registry — `aws_bedrockagent_knowledge_base`: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagent_knowledge_base
- Terraform Registry — `aws_s3vectors_vector_bucket`: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3vectors_vector_bucket
- Terraform Registry — `aws_s3vectors_index`: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3vectors_index

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **None yet for IaC or Python.** Repo currently contains only the Hugo workshop scaffold (config.toml, content/{vi,en}, layouts/, themes/hugo-theme-learn submodule, .github/workflows/ Hugo deploy). Phase 1 is the first phase to introduce both Terraform and any AWS resource code — greenfield IaC.

### Established Patterns
- **Hugo-only repo so far** — anything we add must coexist with the existing Hugo deploy pipeline without breaking it. Terraform code goes in a new top-level directory (likely `infra/` or `terraform/`) so it never appears in the Hugo build output.
- **No emojis in code/logs** (CLAUDE.md mandate) — `verify-kb.sh` and any stdout text obeys this.
- **`uv` for any Python**, never `pip`/`python3` (CLAUDE.md). Phase 1 doesn't introduce Python yet — the verify script is bash. If Python testing is added later it goes through `uv run`.

### Integration Points
- **Phase 2 consumes:** `kb_id` and `kb_arn` outputs from this module to build the Pipecat tool's `Retrieve` call and to scope the Pipecat task role's `bedrock:Retrieve` policy.
- **Phase 4 consumes:** the `force_destroy = true` buckets, the `verify-kb.sh` script (inverted assertion), and the documented manual sync command for the cleanup verification chapter.
- **Phase 5 docs reference:** the per-SKU markdown files as workshop-walkthrough source material (learner copies them into their own bucket); RUNBOOK.md content is folded into the Hands-on chapter.

</code_context>

<deferred>
## Deferred Ideas

- **`pricing-faq.md`** (financing, trade-in, AppleCare) — backlog or v2; keeps Phase 1 minimal and deterministic.
- **Wrapper sync script `bin/kb-sync.sh`** — explicitly rejected; manual `aws bedrock-agent start-ingestion-job` is more teachable and avoids extra surface to maintain.
- **Auto-sync via Terraform `null_resource` + AWS CLI** — explicitly rejected; couples provisioning with side-effect that can fail silently and pollutes state.
- **Random-suffix resource naming for re-apply safety** — explicitly rejected; recovery path is `terraform destroy` + re-apply, documented in RUNBOOK.md.
- **Remote Terraform backend (S3 + DynamoDB)** — out of v1 scope; documented as "next step" only.
- **Consumer `bedrock:Retrieve` role with Pipecat trust policy** — Phase 2 (created alongside the Pipecat task role).
- **Pytest-based KB retrieve test in CI** — Phase 2+ once the Python `uv` toolchain lands; bash `verify-kb.sh` covers v1.
- **Bedrock Guardrails (PII redaction)** — out of v1 per PROJECT.md; revisit when handling real user data.
- **OpenSearch Serverless variant chapter** — v2 advanced topic per ADV-04.

</deferred>

---

*Phase: 01-knowledge-base-foundation*
*Context gathered: 2026-05-05*
