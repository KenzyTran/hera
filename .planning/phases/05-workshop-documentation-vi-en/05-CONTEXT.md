# Phase 5: Workshop Documentation (vi/en) - Context

**Gathered:** 2026-05-07
**Status:** Ready for research and planning

<domain>
## Phase Boundary

Phase 5 ships the **bilingual vi/en Hugo workshop content** that lets a Cloud Clubs learner stand up the Phase 1-4 system in their own AWS account end-to-end and tear it down to zero. The system is already built, deployed, verified, and documented in `RUNBOOK.md` (paste-style operator runbook, ~35K). Phase 5 turns that operator-facing runbook + working source into a **learner-facing, FCJ-format Hugo site** with screenshots at the unavoidable AWS-Console choke points and English-only chatbot speech but bilingual documentation.

In scope: 5 chapters published in both vi and en under existing `content/{vi,en}/{1-introduction, 2-preparation, 3-hands-on, 4-cleanup, 5-summary}/` skeleton. Phần 3 Hands-on is split into 5 sub-pages (3.1 KB → 3.2 Pipecat local → 3.3 Deploy AgentCore → 3.4 Web widget → 3.5 Observability) matching the Phase 1-4 build order. Phần 1, 2, 4, 5 stay single-page each. Code snippets use **inline copy-paste with footer "Source:" reference** to source files (no Hugo readFile shortcode, no CI extract+grep gate). Screenshots are **minimal** — only at AWS Console steps that have no CLI alternative (Bedrock model access enable, Billing Alerts toggle, AgentCore service-quota request) plus 2-3 hero shots (deployed widget UI, CloudWatch dashboard, cleanup-verify output). Region default for learner snippets = `ap-northeast-1` (matches instructor) so snippets and screenshots are 1:1 reusable. Learner builds + pushes their own container to their own ECR (full understanding path; no instructor public-ECR fallback). Top 5-7 pitfall callouts (DOC-10) embedded at the moments learners hit them via `hugo-theme-learn` `notice` shortcode. Per-chapter copy-paste code blocks (DOC-11) and `config.toml` baseURL/title placeholders replaced with the actual GitHub Pages URL. CI parity check (DOC-12) = minimal file-count parity (count `_index.md` + sub-pages under `content/vi` vs `content/en`, fail if not equal). vi-first authoring → translate to en in same plan/commit so parity check never fails.

Out of scope: Hugo theme migration `learn` → `relearn` (deferred v2 per PROJECT.md); custom shortcode for code-include from source (rejected in favor of inline+footer); CI snippet extract+grep against source (rejected as overkill given source frozen post-Phase 4); per-section heading parity or shortcode-aware parity in DOC-12 (rejected as too noisy for translation re-wording); full UI walkthrough screenshots (~50-80 images — rejected as maintenance burden when AWS Console UI changes); GIF/video for complex flows (deferred — minimal screenshots cover the must-haves); pre-built instructor public ECR image (rejected — undermines "their own AWS account" core promise); us-east-1 or "pick nearest region" parametrization (rejected — adds cost-explainer + multi-region screenshot burden); Twilio voice channel chapter (v2); Cognito SSO / multi-tenant chapters (v2); ECS Fargate alternative deployment chapter (deferred to ADV-04 v2); multi-agent routing chapter (ADV-01 v2); language-detection chatbot chapter (I18N-01 v2). Re-publishing the Vietnamese transcript from the original ElevenLabs+n8n+Gemini source material is also out — that material was reference for use-case, not workshop content.

</domain>

<decisions>
## Implementation Decisions

(Numbering continues from Phase 4 D-39. Phase 5 starts at D-40.)

### Chapter granularity & file shape

- **D-40: Phần 3 Hands-on splits into 5 sub-pages.** Layout: `content/{vi,en}/3-hands-on/{3.1-knowledge-base, 3.2-pipecat-local, 3.3-deploy-agentcore, 3.4-web-widget, 3.5-observability}/_index.md`. Naming convention `<chapter>.<sub>-<slug>` matches existing `1.1-prerequisites.md` precedent in the skeleton. Each sub-page gets its own `weight` in front matter (3.1=1, 3.2=2, …) so `hugo-theme-learn` sidebar and next/prev nav are auto-correct. Parity check is trivial: each `content/vi/3-hands-on/3.X-*/_index.md` must have a matching `content/en/3-hands-on/3.X-*/_index.md` with the same slug.
- **D-41: Phần 1, 2, 4, 5 stay single-page each — `_index.md` only.** Phần 2 Preparation has ~6 setup gates (AWS account, Bedrock Nova 2 Sonic + Titan v2 + AgentCore model access, install AWS CLI / Terraform / uv Python, configure creds, cost expectation) but stays one long page with H2 (`## `) sections. Rationale: Phần 2 is shorter than Phần 3 build flow; learner reads top-down as a checklist before entering hands-on; no benefit from sidebar nav between Preparation sub-steps. Phần 1 (intro + architecture diagram), Phần 4 (3-step cleanup quy trình from RUNBOOK), Phần 5 (cost recap + roadmap) are all single-narrative.
- **Total file count:** 4 single-page Phần × 2 langs = 8 + 5 sub-pages × 2 langs = 10 + 5 chapter `_index.md` × 2 langs = 10 → **28 markdown files** across `content/{vi,en}/`. Plus existing `content/en/1-introduction/1.1-prerequisites.md` to either repurpose or remove (planner decides).

### Code snippet sourcing & drift discipline

- **D-42: Inline copy-paste with footer "Source:" reference.** Each fenced code block is followed by an italic line `*Source: agent/hera_agent/main.py — Phase 2 Plan 02-01*` (or equivalent path + phase + plan id). No Hugo `readFile` shortcode (custom layout work for low marginal benefit; theme is deprecated). No CI extract+grep gate (rejected as overkill given source is frozen post-Phase 4). Drift risk is bounded because Phase 5 is the last v1 phase — source code is stable. If a post-launch source edit happens, the source path footer makes manual sync trivial (grep the footer, re-paste the block).
- **D-43: Snippet path = relative repo path.** Footer paths are repo-relative (`agent/hera_agent/main.py`, not `C:\Users\...` and not URL). Lets readers `cat` or open in their cloned repo. No GitHub permalink with SHA — it would drift on every rebase and add maintenance.

### Screenshot strategy

- **D-44: Minimal screenshots — only Console-mandatory steps + 2-3 hero shots.** Screenshot inventory (~10-15 total):
  - **Mandatory Console UI** (no CLI alternative):
    1. Bedrock Console → Model Access → request access for `amazon.nova-sonic-v1:0` + `amazon.titan-embed-text-v2:0` in ap-northeast-1.
    2. AWS Console → Billing → Billing Preferences → tick "Receive Billing Alerts" (RESEARCH A1 from Phase 4; one-time per account).
    3. Service Quotas Console → Bedrock AgentCore → request increase to concurrency cap (D-30 from Phase 3, default 10 → demo cap 2).
  - **Hero shots** (visible win for learner):
    4. Deployed widget UI on `https://<their-cloudfront>.cloudfront.net/` (Apple Store light theme, idle state).
    5. CloudWatch dashboard `hera-prod` with 5 panels populated by their own traffic.
    6. `bin/cleanup-verify.sh` terminal output showing all-green PASS.
  - **Optional supporting**: deployed AgentCore Runtime in Bedrock console (1 shot proving runtime READY); CloudFront distribution status=Deployed; ECR image manifest list showing arm64+amd64 children. Planner picks 2-3 from this set if needed for visual breaks.
- **D-45: Screenshot storage path.** `static/images/<phase>/<filename>.png` mirroring chapter slugs (e.g., `static/images/3.3-deploy-agentcore/console-bedrock-model-access.png`). Annotations rendered into the image at capture time (red box + arrow + text label) using whatever tool the operator already has — no hard tool lock; any annotated PNG works.
- **D-46: No GIF / video.** Complex flows (browser voice loop demo, model access multi-region toggle, cleanup-verify run) stay as screenshots + text. Rejected GIFs to keep static asset size down and avoid the "GIF rendering blank in some browsers" failure mode. Demo URL `https://dg0w939ktclw6.cloudfront.net/` is the live walkthrough — RUNBOOK pointer for "see it run yourself".

### Region defaults & deploy path for learner

- **D-47: Region default = `ap-northeast-1` for every learner snippet.** Snippets, screenshots, Terraform variable defaults, AWS CLI `--region` flags, model access enablement instructions all use `ap-northeast-1`. Rationale: snippets and screenshots are 1:1 reusable from instructor's working setup; Sonic + AgentCore + KB all available in ap-northeast-1; latency from VN (primary audience) is best. Trade-off: learners outside APAC see slightly higher latency — documented as a one-line note in Phần 1 Architecture ("ap-northeast-1 chosen for VN audience; us-east-1 / us-west-2 / eu-north-1 also support Nova 2 Sonic + AgentCore — change `region` variable in `infra/envs/prod/terraform.tfvars` if you prefer"). No multi-region snippet templating; no parametrization beyond the single Terraform variable that already exists.
- **D-48: Learner builds + pushes their own container to their own ECR.** Phần 3.3 Deploy AgentCore mainline path = `bin/push-image.sh` against the learner's own AWS account. Multi-arch buildx + immutable tag = `git rev-parse --short HEAD` (per Plan 03-03 D-X). Requires Docker Desktop with buildx support — Phần 2 Preparation lists this as a tool gate. Rejected pull-from-instructor's-public-ECR option because (a) it would undermine the workshop's core promise ("their own AWS account end-to-end"), (b) instructor public ECR adds permission setup + ongoing maintenance, (c) the learner's grasp of `--provenance=false`/`--sbom=false`/IMMUTABLE-tag/ECR auth is the actual deploy lesson. No hybrid fallback in v1; if a learner can't run Docker, they can either install Docker Desktop or follow up out-of-band with the instructor.

### vi/en authoring & CI parity

- **D-49: vi-first authoring → translate to en in the same plan + commit.** User writes Vietnamese natively (project memory: chat in tiếng Việt; planning files English). Workshop chapter authoring is the exception: vi page first, en translation in the same atomic plan commit so the parity check never trips a half-shipped chapter. Each plan commits **both** `content/vi/<chapter>/_index.md` and `content/en/<chapter>/_index.md` together. Translation can lean on Claude assistance — terminology lock from `i18n/{vi,en}.toml` + the System Prompt phrasing (English) where applicable.
- **D-50: DOC-12 CI parity check = minimal file-count.** Bash script (~20 lines) under `bin/check-i18n-parity.sh` that:
  1. Counts `_index.md` files under `content/vi` and `content/en` — must be equal.
  2. For each `content/vi/<path>/_index.md`, asserts `content/en/<path>/_index.md` exists (and vice versa).
  3. Exit 0 on parity, exit 1 with diff list on mismatch.
  - Wired into `.github/workflows/deploy.yml` as a pre-build step. Fails the PR if vi/en diverge in file structure.
  - Rejected per-section heading parity (false positives when translation rewords headings) and shortcode-aware parity (over-engineering for v1; revisit in v2 if real drift is observed).

### Pitfall callouts (DOC-10)

- **D-51: Use `hugo-theme-learn` built-in `{{% notice %}}` shortcode for pitfalls.** Theme supports `notice info|warning|tip|note`. Pitfall callouts (top 7-8) get `notice warning` placement at the moment learners are about to hit them, not in a separate FAQ chapter. Inventory locked to:
  1. **8-min Sonic stream cap** — Phần 3.2 (Pipecat local) where SessionContinuationParams comes up.
  2. **Audio sample rate (16kHz in / 24kHz out)** — Phần 3.2 (Pipecat local) where AudioConfig defaults are explained.
  3. **Bedrock model access enablement (per-region, per-model)** — Phần 2 Preparation.
  4. **HTTPS required for browser microphone** — Phần 3.4 (Web widget) where local-vs-CloudFront comes up.
  5. **Billing alarm (24h propagation + Billing Alerts toggle one-time)** — Phần 3.5 (Observability).
  6. **Tool-use schema (Sonic strict on JSON shape)** — Phần 3.2 (Pipecat local) where `register_function` is shown.
  7. **Bilingual parity (CI fails PR if vi/en file count diverges)** — Phần 1 Introduction (workshop conventions) or DOC-12 author note.
  8. **KB sync delay (post-ingestion attempt-1 success not guaranteed; documented retry pattern in `bin/verify-kb.sh`)** — Phần 3.1 (KB).
  Planner may reorder, merge, or shift placement based on chapter flow but must include all 8 in the v1 site.

### `config.toml` + GitHub Pages cleanup

- **D-52: `config.toml` placeholders replaced.** Current state has `baseURL = "https://YOUR_GITHUB_USERNAME.github.io/YOUR_REPO_NAME/"` + `title = "Workshop Title"` + `params.author = "Your Name"` + `params.description = "Workshop description"`. Planner replaces with actual repo values: `baseURL` from `git remote get-url origin` (KenzyTran's GitHub Pages URL), `title` = "Hera — AWS Voice Agent Workshop", `params.description` = one-line FCJ blurb in vi (defaultContentLanguage), `params.author` = AWS Cloud Clubs Vietnam (or learner-facing org name). Same `themeVariant = "workshop"` and `defaultContentLanguage = "vi"` stay.
- **D-53: Existing `1.1-prerequisites.md` repurposed or removed.** `content/en/1-introduction/1.1-prerequisites.md` is the only existing sub-page from the FCJ template. Planner decides: either repurpose into "1.1 Prerequisites" sub-page under Phần 1 (then Phần 1 also gets a sub-page split — re-evaluate D-41 for Phần 1), or remove and fold its content into the single-page Phần 1 + checklist into Phần 2.

### Cost recap numbers (Phần 5 Summary + Phần 2 Preparation)

- **D-54: Cost numbers = ranges informed by instructor's actual usage, not a single point estimate.** Phần 2 Preparation sets expectation: "~$2-5 USD for a 2-hour workshop session if you tear down per Phần 4". Phần 5 Summary breaks down by service (Bedrock Sonic streaming = $X-Y / hour, S3 Vectors storage = $Z / month, AgentCore Runtime = $W / hour active, CloudFront + S3 widget = ~$0.10 / day, ECR storage = ~$0.10 / image / month). Numbers sourced from actual Phase 1-4 spend (instructor reads Cost Explorer 24h after one full demo session; planner pulls those numbers into the chapter at planning time). Single point estimates are brittle to AWS pricing changes — ranges absorb pricing drift.

### Architecture diagram (Phần 1 DOC-01)

- **D-55: Diagram tool — Mermaid sequence + component diagram inline in Markdown.** `hugo-theme-learn` supports Mermaid via `{{< mermaid >}}` shortcode (or fenced ` ```mermaid `). One component diagram (Browser → CloudFront → presigner Lambda → AgentCore Runtime → Sonic + KB Retrieve), one sequence diagram (record button click → mic capture → WS upgrade → bidi stream → audio playback). Mermaid renders client-side, no static image to maintain, parity-safe (same Mermaid source in both vi and en, only labels translated). If theme Mermaid support is broken (deprecated upstream), fallback = ASCII boxes-and-arrows in fenced ` ``` ` block (still parity-safe, less pretty).

### Locked decisions carried forward (NOT re-litigated here)

- **From Phase 1 (D-01..D-16):** zero IAM wildcards (D-13 — relevant when Phần 2 shows learner-side IAM); region default `ap-northeast-1` override `us-east-1` (D-14 — Phần 2 default snippet matches D-47); fixed names no `random_id` (D-12 — snippets show fixed names verbatim).
- **From Phase 2 (D-17..D-23):** Pipecat 1.1.0 + Python 3.12 (Phần 2 install gate + Phần 3.2 snippet); explicit `os.environ` static creds for AWSNovaSonicLLMService (Phần 3.2 snippet); FastAPI `/ping` + `/ws` (+ Phase 4's `/invocations`) on port 8080 (Phần 3.2 + 3.3 snippet); multi-arch container same-artifact contract (Phần 3.3 build snippet).
- **From Phase 3 (D-24..D-30):** hybrid IaC = Terraform owns everything except AgentCore Runtime which is CDK Python (Phần 3.3 explains this trade-off explicitly per DOC-10 pitfall slot or sidebar); $5/day banner copy + threshold (Phần 3.4 widget snippet shows verbatim banner; Phần 3.5 observability + Phần 5 cost recap match); AgentCore concurrency cap=2 (D-30 documented manual quota request — Phần 3.5 screenshot D-44 #3); WSS via SigV4 presigner Lambda Function URL (Phần 3.4 widget snippet shows the bridge); custom domain deferred (Phần 3.4 sidebar callout).
- **From Phase 4 (D-31..D-39):** `/invocations` route + AgentCore HTTP protocol (Phần 3.3 snippet shows the route); CloudWatch dashboard `hera-prod` + 2 op alarms + 1 billing alarm cross-region (Phần 3.5 snippet + screenshot D-44 #5); `bin/cleanup-verify.sh` 19 read-only checks (Phần 4 Cleanup snippet + screenshot D-44 #6); 24h Cost Explorer paste-line lives in RUNBOOK as 24h-deferred manual section, mirrored into Phần 4 chapter; D-35 manual-stop fallback for cost circuit-breaker (Phần 3.5 explains the trade-off); D-36 no per-IP rate limit (Phần 3.5 explains AgentCore concurrency cap=2 is the gate).
- **Demo budget rule (project memory 2026-05-06):** Phase 5 is documentation-only — no new AWS deploys, no extra Bedrock streaming smoke. Cost recap (D-54) reuses Phase 4 instructor spend; doesn't trigger another billable run. Screenshots taken once from existing live state.
- **No-scope-creep rule (project memory 2026-05-07):** Stick to DOC-01..12 literally. No "also add Twilio chapter", no "also do theme migration", no "also build a CMS for chapter editing".

### Claude's Discretion (planner / researcher / executor decides)

- Wave structure for Phase 5 plans (one plan per chapter? one plan per langauge pair? mega-plan? planner picks based on file-disjoint parallelism and review burden).
- Front-matter shape — `weight`, `chapter: true`, `pre`, `disableToc`, theme-specific keys — planner picks from `hugo-theme-learn` docs + the existing `_index.md` files as precedent.
- Whether `i18n/{vi,en}.toml` keys need new additions (UI strings the theme reads) or the existing keys cover everything.
- Whether `config.toml` needs additional `[[menu.shortcuts]]` entries for cross-links (e.g., GitHub repo, RUNBOOK, instructor demo URL).
- Exact Mermaid diagram source (D-55) — researcher / planner can sketch from existing `RUNBOOK.md` deploy section + Phase 3 / 4 SUMMARY architecture notes.
- Translation cadence within a single plan — vi+en authored in same plan but planner picks whether vi block is finished first then en, or interleaved per section.
- Whether `bin/check-i18n-parity.sh` needs to be the first commit of Phase 5 (test-first) or land alongside the first chapter PR (test-with-content).
- Whether Phần 2 Preparation cost-expectation section duplicates Phần 5 cost recap or just forward-references it.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project-level mandates
- `.planning/PROJECT.md` — core value (learner deploys to their own AWS account end-to-end), locked stack, scope rules, key decisions table.
- `.planning/REQUIREMENTS.md` — Phase 5 requirement IDs DOC-01..12 (12 total) lines 60-75.
- `.planning/ROADMAP.md` — Phase 5 goal + 5 success criteria (lines 135-146); Phase 1-4 status references at lines 153-159.
- `.planning/STATE.md` — current state including the 5 deferred items in 04-HUMAN-UAT.md (lines 145-153) — none of which block Phase 5.
- `CLAUDE.md` / `AGENTS.md` — no emojis (workshop content + code blocks); concise; latest APIs as of NOW; uv-only Python.
- `RUNBOOK.md` (~35K lines, paste-style operator runbook) — **the operational source-of-truth** Phase 5 chapters translate into learner-facing tone. Every Phần 3.x sub-chapter has a corresponding RUNBOOK section to mirror.

### Cross-phase research (informational)
- `.planning/research/SUMMARY.md` — original architecture research (AgentCore-pivot annotations).
- `.planning/research/STACK.md` — locked stack rationale.
- `.planning/research/PITFALLS.md` — full pitfall inventory; D-51 picks top 7-8 from this for the workshop.
- `.planning/research/ARCHITECTURE.md` — diagram source material for D-55 Mermaid.

### Prior phase decisions & evidence (carry-forward; quoted in chapters via "Source:" footers)
- `.planning/phases/01-knowledge-base-foundation/01-CONTEXT.md` — D-12, D-13, D-14 (verbatim shown in Phần 3.1 snippets).
- `.planning/phases/01-knowledge-base-foundation/01-VERIFICATION.md` — live KB id `BKXE19AH89`, account 851725411875, top-score 0.86 evidence (Phần 3.1 verify section).
- `.planning/phases/02-pipecat-voice-agent-local/02-CONTEXT.md` — D-19 transport WSS, D-20 multi-arch container, D-21 in-memory state, D-22 consumer policy (Phần 3.2 + 3.3).
- `.planning/phases/03-agentcore-deploy-web-widget-public-demo-url/03-CONTEXT.md` — D-24..D-30 (Phần 3.3 + 3.4 + 3.5 trade-off explanations).
- `.planning/phases/04-observability-cost-control-cleanup/04-CONTEXT.md` — D-31..D-39 (Phần 3.5 + Phần 4 chapters).
- All `*-SUMMARY.md` per plan — source of code snippets, deviation notes, and "what we learned" callouts that populate Phần 1 Introduction's "why this stack" section.

### Existing assets to extend
- `config.toml` — replace placeholders (D-52); keep `defaultContentLanguage = "vi"`, `defaultContentLanguageInSubdir = true`, `themeVariant = "workshop"`.
- `content/{vi,en}/_index.md` — replace template "Workshop Title" copy with Hera intro; keep `{{% children depth="1" %}}` shortcode.
- `content/{vi,en}/{1-introduction, 2-preparation, 3-hands-on, 4-cleanup, 5-summary}/_index.md` — currently template stubs; Phase 5 fills with real content.
- `content/en/1-introduction/1.1-prerequisites.md` — repurpose or remove (D-53).
- `themes/hugo-theme-learn/` — git submodule; do NOT touch (locked v1, theme deprecated upstream); use built-in `notice` (D-51) and `mermaid` (D-55) and `children` shortcodes.
- `i18n/{vi,en}.toml` — UI strings the theme reads; add new keys only if Phần content needs them (planner decides).
- `layouts/partials/` — existing AWS Cloud Clubs branding partials (logo, header customization); leave as-is unless a chapter introduces a custom layout need.
- `static/` — image storage destination (D-45 `static/images/<chapter>/`).
- `.github/workflows/deploy.yml` — Hugo → GitHub Pages deploy; D-50 wires `bin/check-i18n-parity.sh` as a pre-build step.
- `RUNBOOK.md` — primary content source for Phần 3 + Phần 4. Phase 5 translates RUNBOOK paste-style ops into learner-facing tutorial tone with screenshots at the choke points.
- All `bin/*.sh` scripts (`verify-kb.sh`, `push-image.sh`, `build-widget.sh`, `smoke-deploy.sh`, `smoke-voice.sh`, `cleanup-verify.sh`, `run-agent-local.sh`, `run-agent-docker.sh`) — Phần 3 + Phần 4 quote these verbatim with footer Source: refs.
- `agent/`, `infra/`, `cdk/`, `frontend/` source trees — copy-paste source for inline snippets per D-42.

### External references
- Hugo docs: https://gohugo.io/content-management/multilingual/ — multilingual site config (already mostly satisfied by existing `config.toml`).
- `hugo-theme-learn` docs: https://learn.netlify.app/en/shortcodes/ — `notice`, `mermaid`, `children` shortcode shapes (theme deprecated but docs still live; planner uses these for D-51 + D-55).
- AWS docs: Bedrock model access enablement (per-region toggle, screenshot D-44 #1).
- AWS docs: Billing Alerts preference toggle (Phase 4 RESEARCH A1, screenshot D-44 #2).
- AWS docs: Service Quotas Bedrock AgentCore concurrency request (D-30, screenshot D-44 #3).
- AWS Cost Explorer `GetCostAndUsage` API — RUNBOOK 24h paste-line referenced from Phần 4.
- AWS blog: [Deploy voice agents with Pipecat and Amazon Bedrock AgentCore Runtime — Part 1](https://aws.amazon.com/blogs/machine-learning/deploy-voice-agents-with-pipecat-and-amazon-bedrock-agentcore-runtime-part-1/) — primary blueprint reference; Phần 1 Introduction may cite for "where this architecture comes from".
- FCJ workshop format reference (existing AWS Cloud Clubs Vietnam workshops on GitHub Pages) — tone + structure precedent for Phần 1 Introduction styling.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`content/{vi,en}/` skeleton** — 5 chapter `_index.md` files already exist as template stubs with `weight` set, `pre` heading prefix, and `chapter: true` for Phần 3. Phase 5 replaces template copy with real content; structure is already there.
- **`config.toml`** — multilingual config (`defaultContentLanguage = "vi"`, `defaultContentLanguageInSubdir = true`, `[languages.vi]` + `[languages.en]` blocks) is correct. Only `baseURL` / `title` / `params.*` placeholders need replacing per D-52.
- **`i18n/{vi,en}.toml`** — UI string translations for the theme. Planner can extend if a chapter introduces a new UI string.
- **`themes/hugo-theme-learn/`** — git submodule; built-in shortcodes `notice`, `mermaid`, `children`, `attachments`, `expand`, `tabs` available. D-51 uses `notice` for pitfalls, D-55 uses `mermaid` for architecture diagram.
- **`layouts/partials/`** — AWS Cloud Clubs branding (logo + header) already integrated; chapters inherit automatically.
- **`.github/workflows/deploy.yml`** — Hugo build + GitHub Pages deploy already wired; D-50 adds `bin/check-i18n-parity.sh` as a pre-build step.
- **`RUNBOOK.md`** — operational source-of-truth that Phase 5 translates into learner-facing tutorial chapters. Every operational quy trình already documented; Phase 5 reframes for FCJ tone with screenshots.
- **All `bin/*.sh`** — paste-style operator scripts; Phần 3 + Phần 4 quote verbatim with footer source refs (D-42).
- **`agent/`, `infra/`, `cdk/`, `frontend/`** — source trees; snippet source per D-42.
- **`docs/`** — appears in repo root (untracked per git status); planner inspects whether existing notes belong in workshop or stay as internal docs.

### Established Patterns
- **No emojis in any content** (CLAUDE.md mandate; chapters are content but the rule still applies — even the workshop docs).
- **Conventional commits scoped to plan id** (`docs(05-01): add Phần 1 vi+en` or `feat(05-01): publish chapter 1`). Phase 5 commits follow this.
- **Atomic commits per logical unit** — vi+en pair for one chapter is one commit (D-49 ensures parity check never fails mid-PR).
- **uv-only Python** — Phase 5 introduces no new Python; `bin/check-i18n-parity.sh` is bash (matches D-37 pattern).
- **Paste-style FCJ tone** — RUNBOOK is the precedent; chapters follow.
- **Latest APIs as of NOW** — Hugo current release; theme docs current; AWS console screenshots taken at time of authoring (will be re-taken if AWS UI drifts in v2).

### Integration Points
- **Hugo build → GitHub Pages:** existing `.github/workflows/deploy.yml` covers; D-50 adds parity gate before build.
- **Source trees → chapter snippets:** authoring-time copy-paste with footer Source: ref (D-42); no build-time link.
- **`hugo-theme-learn` shortcodes → chapter content:** `notice` (D-51), `mermaid` (D-55), `children` (chapter index pages), built-in syntax-highlighted code blocks via Goldmark.
- **`i18n/{vi,en}.toml` → theme UI strings:** Phase 5 may extend if a chapter UI element needs a new string.
- **Phase 1-4 evidence → workshop credibility:** every chapter cites a concrete plan (e.g., "Plan 03-04 deployed the AgentCore Runtime — see `03-04-SUMMARY.md` for the live result"). Builds learner trust that the workshop matches a system that actually ran.

</code_context>

<specifics>
## Specific Ideas

- **Phần 3 sub-page slugs locked:** `3.1-knowledge-base`, `3.2-pipecat-local`, `3.3-deploy-agentcore`, `3.4-web-widget`, `3.5-observability`. Mirrors RUNBOOK section order + Phase 1-4 build order.
- **Total file budget:** ~28 markdown files (D-40+D-41) + 10-15 PNG screenshots (D-44) + 1 bash script (`bin/check-i18n-parity.sh`) + 1 `config.toml` edit + 1 `.github/workflows/deploy.yml` edit + maybe 1 `i18n/*.toml` extension. Minimal new code surface.
- **Pitfall callouts inventory locked at 8 (D-51):** 8-min Sonic stream cap, audio sample rate, model access enablement, HTTPS-for-mic, billing alarm propagation, tool-use schema strictness, bilingual parity (DOC-12), KB sync delay.
- **Screenshot count target ~10-15 total (D-44):** 3 mandatory Console + 3 hero + 2-4 supporting (planner picks).
- **Region default = `ap-northeast-1` everywhere (D-47):** every snippet, every screenshot region selector, every CLI `--region` flag.
- **Container build path = learner's own ECR (D-48):** Phần 3.3 Deploy mainline = `bin/push-image.sh` against learner's account.
- **Cost recap target ~$2-5 USD per 2-hour workshop session (D-54):** range per Phần 5 + Phần 2 expectation; refined at planning time from instructor's actual Cost Explorer 24h-after-Phase-4 data.
- **Architecture diagram = Mermaid component + sequence (D-55):** Phần 1 includes at least these two; ASCII fallback if theme Mermaid breaks.
- **`config.toml` baseURL target:** derived from `git remote get-url origin` — planner reads at planning time. KenzyTran is the git user; expect `https://KenzyTran.github.io/hera/` or similar.
- **CI parity script location:** `bin/check-i18n-parity.sh` (matches `bin/verify-kb.sh` + `bin/cleanup-verify.sh` naming pattern).

</specifics>

<deferred>
## Deferred Ideas

(Items raised or implied during discussion that belong outside Phase 5 scope.)

- **Hugo theme migration `learn` → `relearn`** — explicitly v2 per PROJECT.md. Theme is deprecated upstream but functional; migration adds scope without v1 benefit.
- **Custom Hugo `code-include` shortcode** for build-time source extraction — rejected per D-42 in favor of inline+footer. Capture for v2 if real drift becomes painful post-launch.
- **CI snippet extract+grep gate** — rejected per D-42 (overkill while source is frozen). Capture for v2 if a learner-reported bug forces a source edit + the docs get stale.
- **Pull instructor's public ECR image as deploy fallback** — rejected per D-48 (undermines core promise). Capture for v2 if instructor wants a "can't run Docker?" branch documented.
- **us-east-1 / parametrized region path** — rejected per D-47 (multi-region adds cost-explainer + screenshot maintenance burden). Capture for v2 expansion if non-APAC adoption becomes meaningful.
- **Full UI walkthrough screenshots** (~50-80 images) — rejected per D-44 (maintenance burden + conflicts with CLI-first system tone). Capture for v2 if learner feedback shows screenshots-everywhere is preferred over CLI-first.
- **GIF / video for complex flows** — rejected per D-46 (file size + browser compat). Live demo URL `https://dg0w939ktclw6.cloudfront.net/` is the "see it run" path. Capture for v2 if a chapter genuinely needs motion.
- **Per-section heading parity** in DOC-12 CI — rejected per D-50 (false positives on translation re-wording). Capture for v2 if half-translated PRs become a problem.
- **Shortcode-aware parity** in DOC-12 CI — rejected per D-50 (over-engineering for v1).
- **Twilio voice channel chapter** — explicitly v2 per PROJECT.md; tracked as TWIL-01..03.
- **Cognito SSO / multi-tenant chapter** — v2 per PROJECT.md; tracked as AUTH-01..02.
- **ECS Fargate alternative deployment chapter** — v2 per PROJECT.md; tracked as ADV-04.
- **Multi-agent routing chapter** — v2 per PROJECT.md; tracked as ADV-01.
- **Language-detection chatbot chapter** (Sonic speaks vi) — v2 per PROJECT.md; tracked as I18N-01..02.
- **Custom domain + ACM cert chapter** — deferred from Phase 3 D-26 to v2; not part of v1 workshop.
- **Pre-built CMS / chapter-editor** — out of scope; chapters edited as Markdown in repo.
- **Re-publishing original ElevenLabs+n8n+Gemini transcript** — origin material was reference for use-case, not workshop content. Phase 5 builds the AWS-native version standalone.

</deferred>

<success_signals>
## What Success Looks Like (for downstream agents)

When research and planning complete, the executor should be able to produce a Phase 5 deliverable that satisfies all 5 ROADMAP success criteria:

1. **All 5 chapters published in vi + en.** Phần 1 (single page), Phần 2 (single page), Phần 3 (5 sub-pages 3.1-3.5), Phần 4 (single page), Phần 5 (single page) under both `content/vi/` and `content/en/` with matching slugs. Hugo `defaultContentLanguageInSubdir = true` makes vi/en URLs first-class. Language switcher in `hugo-theme-learn` works because file structure mirrors.

2. **A fresh learner deploys end-to-end from Phần 2 + Phần 3 alone.** Following the chapters with copy-paste — they enable Bedrock Nova 2 Sonic + Titan v2 + AgentCore model access in `ap-northeast-1`, install AWS CLI / Terraform / uv / Docker Desktop, configure creds, `terraform apply` infra modules, build + push their own container via `bin/push-image.sh`, `cdk deploy hera-agentcore`, build their widget via `bin/build-widget.sh`, open their CloudFront URL, and talk to their voice chatbot. Phase 5 doesn't itself run this — Phase 5 SC#2 is satisfied when chapters faithfully mirror the working RUNBOOK + bin/* scripts.

3. **Cleanup proven via Phần 4 chapter.** Learner pastes `cdk destroy hera-agentcore --force` → `terraform destroy -auto-approve` → `bash bin/cleanup-verify.sh` → script exits 0 with all-green PASS. Phần 4 also includes the 24h-deferred Cost Explorer paste-line per Plan 04-03 D-38.

4. **Pitfall callouts placed at choke points.** All 8 pitfalls from D-51 inventory appear at the moments learners hit them via `{{% notice warning %}}` shortcode (or `notice info` for advisory ones). No FAQ-only chapter — pitfalls live inline with the step that triggers them.

5. **CI parity check fails the build on vi/en file divergence.** `bin/check-i18n-parity.sh` runs as a pre-build step in `.github/workflows/deploy.yml` and exits 1 if `content/vi/**/_index.md` and `content/en/**/_index.md` counts don't match or if a slug is missing in one tree.

Plus implicit must-haves:
- No emojis anywhere in chapters or new code (CLAUDE.md mandate carry-forward).
- All snippets verbatim from frozen Phase 1-4 source with footer "Source: <repo-relative-path> — Phase X Plan XX-XX" reference.
- Region default `ap-northeast-1` in every snippet (D-47).
- Learner deploys to **their own AWS account** — no instructor-shared resources, no public ECR pull (D-48).
- `config.toml` placeholders replaced with real Hera values (D-52).
- `themes/hugo-theme-learn/` git submodule untouched — chapters use only built-in shortcodes.
- vi-first author + en-translated in same plan + same commit (D-49) so parity check never trips on a half-shipped chapter.
- Demo budget honored: Phase 5 makes zero new AWS deploys + zero new Bedrock streaming smoke. All evidence reused from Phase 1-4 live state.

</success_signals>

---

*Phase: 05-Workshop Documentation (vi/en)*
*Context gathered: 2026-05-07*
