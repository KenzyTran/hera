# Feature Research

**Domain:** AWS-native voice AI agent demo + FCJ-format workshop documentation (dual product)
**Researched:** 2026-05-04
**Confidence:** HIGH (Nova 2 Sonic capabilities, Pipecat web transport, FCJ format all verified against official sources)

## Scope Reminder (v1)

Two distinct products under one umbrella, must be triaged separately:

- **Product A — Voice agent demo system:** Web widget only, English-only Sonic speech, Apple Store customer support use case (Apple Watch S11, iPhone 13 Pro Max, MacBook Pro M4 stock & catalog questions). Deployed on real AWS. Twilio, mobile, multilingual chatbot are anti-features for v1.
- **Product B — FCJ workshop docs:** Hugo + hugo-theme-learn, vi/en bilingual, GitHub Pages. Teaches a learner to deploy Product A in their own AWS account.

Core Value (from PROJECT.md): "A learner walks through workshop and successfully deploys voice chatbot on their own AWS, talking to it through browser." Everything else is negotiable.

---

## Product A — Voice Agent System

### Table Stakes (Users Expect These)

The 2026 voice agent market (ElevenLabs Agents, OpenAI Realtime, LiveKit demos) has set hard expectations. Anything missing here makes the demo feel like a 2023 prototype.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Browser microphone capture (WebRTC `getUserMedia`) over WebSocket to Pipecat | Without it the demo can't run; users won't install anything | LOW | Pipecat's `WebSocketServerTransport` + raw PCM frames is the documented path; example exists in `pipecat-examples` |
| Server-side voice activity detection + turn detection | Users expect natural turn-taking, not push-to-talk-with-radio-protocol | LOW | **Built into Nova 2 Sonic itself** — sensitivity is configurable (high/medium/low). No external Silero VAD needed. Workshop should still mention the toggle |
| Barge-in (user can interrupt agent mid-response) | Bar set by ElevenLabs and OpenAI Realtime; without it conversation feels robotic | LOW–MEDIUM | Server-side handled by Sonic; client must stop playback and flush audio queue when interrupt event arrives. Pipecat handles the wiring |
| Streaming audio playback (no "wait, then speak" pause) | Sub-second perceived latency is the headline feature of S2S models | LOW | Pipecat `AudioBufferProcessor` + Web Audio API; play frames as they arrive |
| Tool/function calling to Bedrock Knowledge Base for product lookup | This **is** the demo — without KB lookup it's just chitchat, no business value, doesn't match raw_content.txt use case | MEDIUM | Sonic supports tool use natively; tool definition declares `lookup_product(query)` → calls Bedrock `RetrieveAndGenerate` or `Retrieve` |
| Bedrock Knowledge Base over S3 Vectors with the 3 SKUs (Apple Watch S11, iPhone 13 Pro Max, MacBook Pro M4) | Without product catalog the agent can't answer "do you have iPhone 13 Pro Max in stock?" — the verbatim demo prompt | MEDIUM | One ingestion job, fixed-size chunking is fine for a 3-product catalog. Markdown source files |
| Visible record button with clear states (idle / connecting / listening / agent speaking / error) | Without state feedback users press repeatedly, break the session, blame the demo | LOW | 4-5 visual states; mirror Voice UI Kit conventions |
| Live transcript display (user speech + agent speech) below/beside the button | Accessibility, debuggability, screenshot-friendly for the workshop docs themselves | LOW | Sonic emits text frames alongside audio; Pipecat surfaces them. Append-only log view |
| Microphone permission denied / unavailable error path | First-time users will reject the prompt; demo must explain how to fix | LOW | Catch `NotAllowedError`, `NotFoundError`; show inline help text |
| Public HTTPS endpoint with valid TLS | `getUserMedia` requires secure context. ALB + ACM cert is mandatory | LOW | Workshop teaches ACM + Route53 or self-signed-with-warning fallback |
| CloudWatch logs of session count, latency p50/p95, error rate | Workshop demonstrates an "AWS-native" deployment — observability is part of the lesson | LOW–MEDIUM | One dashboard, 3-4 metrics, 1 alarm. Metric filters on Pipecat container logs |
| Graceful disconnect / session end | Users close tab; backend must release ECS task slot, close Bedrock stream | LOW | Pipecat handles via transport hooks; need to verify Bedrock bidirectional stream is closed cleanly |
| System prompt that constrains agent to Apple Store support persona | Without it, Sonic happily discusses anything; demo loses focus and racks up tokens | LOW | One paragraph in code; workshop highlights it as a teachable moment |

### Differentiators (Defer-able but Valuable)

These elevate the demo from "works" to "this is the workshop I'd recommend." Land them in v1.x once the table-stakes loop is green.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Source citation in transcript ("answered using Apple Watch S11 catalog page") | Shows RAG attribution; teaches a real production pattern | MEDIUM | `RetrieveAndGenerate` returns citations with source URIs; render them as a small chip under the agent reply |
| Per-session cost guardrail (max duration ~3 min, max audio tokens) | Workshop learners share AWS accounts; one runaway session = surprise bill | MEDIUM | Server-side timer in Pipecat pipeline; close stream + display message. Critical for demo on a public URL but skippable for `localhost` first |
| Daily/per-IP rate limit at edge (ALB / API Gateway / WAF) | Public demo URL = abuse magnet; protect Bedrock cost | MEDIUM | API Gateway throttling or WAF rate-based rule. Differentiator because most workshop demos skip this and end up taken down |
| Latency telemetry surfaced in UI (debug mode) | Lets workshop learners *see* the sub-second loop they built; great teaching moment | LOW | Show TTFB to first audio frame; only when `?debug=1` |
| Conversation reset button | Long sessions accumulate context, agent drifts; one-click clean slate | LOW | Frontend disconnect + reconnect; backend already handles |
| Health-check endpoint (`/healthz`) and ECS task autoscaling on session count | Workshop demonstrates real production hygiene | LOW | Pipecat doesn't ship one — add a `/health` route to the same container |
| Light/dark theme + mobile-responsive widget | Workshop screenshots look professional; works on instructor's phone during demo | LOW | Tailwind or plain CSS; not a real product feature, just a demo polish |
| Two voice options (e.g., one masculine + one feminine Sonic voice) | Lets workshop students experiment without code change | LOW | Config-driven; Sonic exposes voice IDs |

### Anti-Features (Do NOT Build for v1)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Twilio Voice phone channel | "Real voice agents are on phones" | Phone number procurement, A2P 10DLC compliance, 2x the integration surface, doubles cost. Already in PROJECT.md Out of Scope | Document as v2 milestone; mention in workshop "Summary" chapter as "what to extend next" |
| Mobile native iOS/Android app | "Looks more like a real product" | App store review, push notifications, native audio plumbing. Web widget already covers the demo | Workshop demo URL works on mobile browsers — that's enough |
| Multi-tenant auth (Cognito / SSO / login screen) | "Production needs auth" | Workshop demo is single-user/personal; Cognito setup adds 30 min to deploy with zero teaching value for the voice loop | API key in query string + ALB rate limit; "real auth" is a v2 chapter |
| Custom voice cloning / fine-tuned voice | "Sounds more on-brand" | Adds a separate ML pipeline; not what learners signed up for | Use Sonic default voices |
| OpenSearch Serverless vector backend | "It's the AWS-recommended vector store" | $200–400/month minimum; kills workshop affordability | S3 Vectors (already locked in PROJECT.md) |
| Vietnamese voice for the chatbot | "Workshop is bilingual, so should the bot be" | Sonic's Vietnamese is weaker; doubles QA; PROJECT.md Out of Scope | English chatbot, bilingual docs only |
| Real-time conversation analytics dashboard (sentiment, intent, dropoff) | "Shows it's enterprise-grade" | Requires QuickSight, Athena, more glue than Pipecat itself. Doesn't help the learner deploy a working bot | Put basic CloudWatch metrics in v1; reference Bedrock Guardrails / Comprehend integration in workshop "Extensions" appendix |
| Saved conversation history across sessions (DynamoDB transcript store) | "Real chatbots remember" | Adds DynamoDB module, IAM, retrieval logic; PII concerns; the demo is one-shot Q&A about products | Stateless sessions; show in-session transcript only |
| Audio recording / playback of past calls | "Useful for QA" | Storage, retention, privacy review, S3 lifecycle policy — workshop scope creep | Anti-feature; mention in "Production hardening" appendix |
| WebRTC (LiveKit / Daily) instead of raw WebSocket | "Lower latency, better networking" | Pulls in LiveKit infra OR pays for Daily; learners must understand TURN/STUN. WebSocket is enough for `< 1s` voice loop and matches AWS reference blog | Plain WebSocket transport. Note in docs that WebRTC is the v2 upgrade path |
| Multi-agent orchestration (router agent → specialist agents like raw_content.txt) | Source transcript shows it; "feels more advanced" | n8n-style multi-agent routing belongs to a follow-up workshop. v1 = single agent + KB tool. Already excluded by "no n8n" decision | Single Sonic session with one tool. v2 workshop can introduce supervisor pattern |
| Streaming agent response to multiple channels at once | "Show it on phone *and* web simultaneously" | Cool demo, zero teaching value | Skip |
| Custom guardrails / PII redaction | "Production needs it" | Bedrock Guardrails works but adds another resource; not the focus | Mention in workshop "Production checklist" appendix; not required for v1 |
| Push-to-talk mode | "More predictable than VAD" | Sonic's whole value prop is natural turn-taking; PTT defeats the purpose and confuses learners | Always-on VAD with a mute button if needed |

---

## Product B — FCJ Workshop Docs

### Table Stakes (FCJ Format Conventions + Workshop Genre)

These are baked into the FCJ format and into what every AWS hands-on workshop ships with. Missing any of these and the workshop "doesn't look like an FCJ workshop."

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| 5-chapter structure: 1-introduction / 2-preparation / 3-hands-on / 4-cleanup / 5-summary | Standard FCJ scaffold; already specified in PROJECT.md and seeded in `content/{vi,en}/` | LOW | Just fill it in; structure is settled |
| Bilingual vi/en content via Hugo multilingual + hugo-theme-learn language switcher | PROJECT.md constraint, audience is VN Cloud Clubs members | LOW (infra) / HIGH (writing) | Switcher works out-of-box; the cost is writing every page twice and keeping them in sync |
| Numbered, ordered pages within each chapter (Hugo `weight` or numeric prefix) | hugo-theme-learn convention; gives learners "next/prev" navigation | LOW | Already conventional in the template |
| Code snippet copy buttons | Every AWS workshop has them; learners run commands by copy-paste; mistyping HCL is rage-quit material | LOW | hugo-theme-learn ships a copy-to-clipboard shortcode/feature |
| Screenshots for AWS Console steps (enable Bedrock model, verify deploy, confirm cleanup) | Console flows change yearly; learners need visual confirmation | MEDIUM | Mostly time cost. Use `static/images/{vi,en}/` or shared `static/images/` with localized captions |
| Architecture diagram in Introduction | Sets mental model before hands-on; standard AWS workshop pattern | LOW | One diagram (draw.io / Excalidraw → PNG); shows browser → ALB → ECS/Pipecat → Bedrock Sonic + KB |
| Cost estimate / "what this costs to run" callout | FCJ explicitly mentions this ("approx 500k VND/month if account well-managed"); learners need to know before they `terraform apply` | LOW–MEDIUM | One table per major resource: Sonic per-minute, Bedrock KB per query, S3 Vectors per GB, Fargate per hour. Cite AWS pricing pages |
| Cleanup chapter with `terraform destroy` + manual verification checklist | FCJ standard; without it learners leak resources and never come back | MEDIUM | Step list: `terraform destroy`, then console check for: KB index, S3 bucket, ECS task, ALB, CloudWatch log groups, IAM roles |
| Prerequisites list at top of "Preparation" (AWS account, Bedrock Sonic enabled, Terraform installed, AWS CLI configured) | Learners hit page 30 and discover they can't proceed = workshop dropout | LOW | Plain bullet list with version numbers |
| Cross-references between vi and en pages (consistent slugs) | Language switcher only works if slugs match | LOW | Already enforced by `content/{vi,en}/` mirrored structure |
| Static images served from `static/images/` | Hugo / FCJ convention; PROJECT.md confirms | LOW | Done by template |
| GitHub Pages deploy via existing Actions workflow | Already in template, mentioned in PROJECT.md Validated requirements | LOW | Already done |
| Each `terraform apply` step preceded by "what you're about to deploy" + followed by "how to verify" | Workshop learning pattern: predict → execute → confirm | LOW | Writing discipline, not infra |

### Differentiators (Defer-able)

These make hera *the* recommended workshop in the AWS Cloud Clubs catalog.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| "Verify your deploy" checkpoint at end of each hands-on sub-section | Learners know they're on track without waiting until the end | LOW | A short callout: "you should now see X in the console" |
| Troubleshooting / FAQ appendix per chapter (or top-level) | Saves the workshop maintainer from answering the same Discord questions weekly | MEDIUM | Common: "Sonic not enabled in region", "Bedrock model access denied", "ECS task fails ELB health check", "WebSocket 403 from ALB" |
| Cost-control sidebar (e.g., "stop here if you only have 1 hour") | Lets learners take a break without leaking resources overnight | LOW | "How to pause" section: scale ECS service to 0, keep KB |
| Inline cost estimate on each `apply` step | Beyond the summary table; learners know "this command costs ~$0.10" | MEDIUM | Time-consuming to keep accurate; high educational value |
| Print-friendly / single-page version | Some learners prefer offline reading; hugo-theme-learn (relearn fork) supports this natively | LOW | Theme feature; opt-in |
| Embedded short video clip of working demo at end of "Hands-on" | Confirms what success looks like; helps debug "is mine broken?" | LOW–MEDIUM | 30-second screen recording; host on YouTube unlisted |
| Glossary / "Concepts" sidebar (Bedrock, Knowledge Base, Pipecat, S2S, VAD) | Audience may not know the jargon; reduces dropout | LOW | One page in chapter 1; cross-link from later mentions |
| "What changed since recording" disclaimer banner with last-verified date | AWS console UI shifts; sets expectation honestly | LOW | Hugo front-matter `lastVerified` + partial template |
| Architecture deep-dive appendix (why Pipecat, why ECS Fargate not Lambda, why S3 Vectors not OpenSearch) | Differentiates a teaching workshop from a copy-paste workshop; matches PROJECT.md "Key Decisions" | MEDIUM | Move/expand the table from PROJECT.md into a learner-friendly chapter |
| Downloadable starter `tfvars` / sample config | Prevents typos and copy-paste fatigue | LOW | Static file in `static/code/`; link from page |
| Cleanup verification script (small bash that checks for orphan resources) | Goes beyond the visual checklist; differentiator vs other FCJ workshops | MEDIUM | One `cleanup-check.sh` shipped in repo |

### Anti-Features (Do NOT Add to Workshop v1)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| In-browser interactive AWS console simulator / sandbox | "Learners shouldn't need their own AWS account" | Massive infra; defeats the entire FCJ premise that learners deploy to *their own* account | Stick to "deploy in your real account, $X estimated" |
| Auto-graded quiz at end of each chapter | "Gamify the workshop" | Hugo doesn't do this natively; needs extra JS/backend; nobody asked for it | Skip |
| Video for every section (full screencast) | "Visual learners" | Production cost is enormous; videos go stale before written docs | One short success-clip in differentiators is enough |
| Comments / discussion section on each page (Disqus, etgiscus, etc.) | "Community engagement" | Moderation burden; spam. Use GitHub Issues or Discord link instead | Single "Get help" page with link to Cloud Clubs Discord + GitHub Issues |
| Real-time collaboration / shared workshop sessions | "Pair learning" | Out of scope; Hugo is static | Skip |
| Auto-generated cost estimator that calls AWS Pricing API | "Accurate live pricing" | API auth from a static site is wrong; Hugo is not the place | Hand-curated cost table, refreshed at milestone boundaries |
| Embed live voice demo iframe inside the workshop docs site itself | "Try before you deploy" | Couples the docs site to a running ECS task; cost; outage risk; hosting in `github.io` doesn't fit the WebSocket backend anyway | Link out to the demo URL; or screen recording |
| 3+ languages (Japanese, Chinese, etc.) | "Reach more learners" | Already 2x writing burden with vi/en; PROJECT.md scope is vi/en | Vi/en only |
| Slack/Discord-bot integration that answers workshop questions automatically | "Workshop AI helper" | Meta-recursion; out of scope; maintenance hell | Discord channel with humans |
| One-click "deploy this workshop's stack to your account" button (e.g., CloudFormation Quick Start) | "Frictionless deploy" | The whole point is teaching learners to *use Terraform*; bypassing it skips the lesson | Workshop teaches `terraform apply`; that's the lesson |
| Screenshots in BOTH languages (vi screenshots vs en screenshots of console) | "Localize fully" | AWS Console has its own language toggle; doubling screenshots means 2x maintenance for tiny gain | Single set of screenshots (English console is universal); captions translated per language |
| In-page "live coding" / runnable Terraform sandbox | "Interactive HCL playground" | Doesn't exist; would require a backend | Static code blocks, copy-button, learner runs locally |

---

## Feature Dependencies

```
Voice Agent System (Product A):

Browser microphone (getUserMedia)
    └──requires──> Public HTTPS endpoint (TLS)
                       └──requires──> ACM cert + ALB

WebSocket transport (Pipecat)
    └──requires──> ECS Fargate task (long-lived process)
                       └──requires──> VPC + subnets + security groups (Terraform)

Tool calling (KB lookup)
    └──requires──> Bedrock Knowledge Base
                       └──requires──> S3 Vectors index
                       └──requires──> Apple catalog markdown ingested
                       └──requires──> IAM role with bedrock:Retrieve permission

Streaming audio playback in browser
    └──requires──> Web Audio API + Pipecat client SDK

Barge-in (client side)
    └──requires──> Sonic emits interrupt event
    └──requires──> Pipecat audio buffer flush hook
    └──enhances──> User experience (table-stakes feel)

Live transcript display
    └──requires──> Sonic text frames + WebSocket text channel
    └──enhances──> Source citation chip (differentiator)

Per-session cost guardrail
    └──requires──> Pipecat pipeline timer
    └──requires──> Public endpoint (otherwise no abuse risk)

CloudWatch dashboards
    └──requires──> Pipecat container emits structured logs
    └──requires──> CloudWatch Logs Insights queries / metric filters

Daily rate limit (WAF/API Gateway)
    └──requires──> Public endpoint
    └──conflicts──> Pure Pipecat WebSocket on raw ALB (need API GW or WAF in front)


Workshop Docs (Product B):

Bilingual vi/en
    └──requires──> Mirrored content/{vi,en}/ structure
    └──requires──> i18n/{vi,en}.toml strings
    └──requires──> Discipline to update both at once (process, not feature)

Hands-on chapter
    └──requires──> Working Terraform modules in repo
    └──requires──> Architecture diagram (introduction chapter)
    └──requires──> Prerequisites verified (preparation chapter)

Cleanup chapter
    └──requires──> Hands-on chapter content
    └──requires──> Knowledge of *every* resource Terraform created
    └──enhances──> Cleanup verification script (differentiator)

Cost estimate
    └──requires──> Final architecture is settled
    └──conflicts──> Adding new resources late (must update cost table every time)

Screenshots
    └──requires──> A working deploy (chicken-and-egg with hands-on chapter)
    └──conflicts──> Frequent UI changes in AWS Console (maintenance burden)

Troubleshooting / FAQ
    └──requires──> First batch of real learner feedback
    └──enhances──> Hands-on chapter (catches issues before they happen)
```

### Dependency Notes

- **Browser mic requires HTTPS:** Hard browser security rule. Workshop's first deploy step must produce a working HTTPS URL or the entire demo is blocked.
- **Tool calling chains all the way back to S3 Vectors:** The KB → S3 Vectors → ingestion job → IAM chain is the single longest dependency in v1; if any link breaks, the agent has nothing useful to say. Treat this as a single phase in the roadmap.
- **Source citations enhance live transcript:** Don't build citations before the transcript is rendering plain text correctly.
- **Cost guardrail vs public endpoint:** If demo stays on `localhost`/instructor laptop, you can skip rate limits. The moment it goes to a public URL, both per-session timer and edge rate limit become near-table-stakes.
- **Cleanup script enhances cleanup chapter:** Write the chapter first (forces you to enumerate resources), then automate.
- **Bilingual is a process, not a feature:** The infrastructure is free; the cost is writing discipline. Treat "ship vi+en together per page" as a roadmap rule, not a feature backlog item.
- **Screenshots conflict with rapid iteration:** Take screenshots only after the hands-on Terraform is frozen for the milestone — otherwise you redo them every commit.

---

## MVP Definition

### Launch With (v1) — Voice Agent System

The minimum needed for the verbatim demo prompt ("do you have iPhone 13 Pro Max in stock?") to work end-to-end on a real AWS deploy.

- [ ] Browser mic → WebSocket → Pipecat → Sonic → audio playback (the loop)
- [ ] Record button with idle/listening/speaking/error states
- [ ] Live transcript (user + agent text)
- [ ] Bedrock KB over S3 Vectors with the 3 SKUs ingested
- [ ] Sonic tool definition `lookup_product(query)` calling KB Retrieve
- [ ] System prompt locking agent to Apple Store support persona
- [ ] Server-side VAD + barge-in (Sonic native)
- [ ] Mic permission denied error path with help text
- [ ] HTTPS endpoint via ALB + ACM
- [ ] CloudWatch logs for the Pipecat container; one dashboard with session count + p95 latency
- [ ] Graceful disconnect on tab close
- [ ] Terraform modules deploying all of the above

### Launch With (v1) — Workshop Docs

- [ ] All 5 chapters populated in vi + en
- [ ] Architecture diagram in chapter 1
- [ ] Prerequisites checklist in chapter 2 (incl. Bedrock Sonic model access enable steps)
- [ ] Hands-on chapter walks through `terraform apply`, KB ingestion, widget test — with screenshots and copy-paste code blocks
- [ ] Cleanup chapter with `terraform destroy` + manual checklist
- [ ] Cost estimate table in summary chapter
- [ ] GitHub Pages deploy working for both languages

### Add After Validation (v1.x)

- [ ] Source citations in transcript (RAG attribution chip)
- [ ] Per-session cost guardrail (3-min timeout, max audio tokens)
- [ ] Edge rate limit (WAF or API Gateway throttle)
- [ ] Conversation reset button
- [ ] Latency telemetry in `?debug=1`
- [ ] Health check endpoint + ECS autoscaling
- [ ] Two voice options (Sonic voice ID config)
- [ ] Workshop: troubleshooting / FAQ appendix
- [ ] Workshop: per-step "verify" callouts
- [ ] Workshop: 30-second success-screencast embed
- [ ] Workshop: glossary page
- [ ] Workshop: "what changed since recording" banner with last-verified date

**Trigger to add v1.x items:** v1 demo proven to work end-to-end in a real AWS account by someone other than the author, AND first cohort of learners has run through workshop and surfaced friction.

### Future Consideration (v2+)

- [ ] Twilio Voice phone channel (PROJECT.md explicit v2)
- [ ] Multi-agent supervisor/router pattern (raw_content.txt parity)
- [ ] Cognito-based auth + per-learner sessions
- [ ] Vietnamese chatbot speech (when Sonic vi quality acceptable)
- [ ] WebRTC transport upgrade
- [ ] DynamoDB conversation history
- [ ] Bedrock Guardrails integration
- [ ] Workshop: cleanup verification script
- [ ] Workshop: deep-dive architecture appendix
- [ ] Workshop: print-friendly export
- [ ] Workshop: 3rd language

---

## Feature Prioritization Matrix

### Voice Agent System

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Browser mic → WebSocket → Sonic loop | HIGH | MEDIUM | P1 |
| KB tool call (lookup_product) | HIGH | MEDIUM | P1 |
| KB ingestion of 3 SKUs over S3 Vectors | HIGH | MEDIUM | P1 |
| Record button states + transcript | HIGH | LOW | P1 |
| Server-side VAD + barge-in | HIGH | LOW (built into Sonic) | P1 |
| HTTPS endpoint | HIGH | LOW | P1 |
| Mic-denied error path | HIGH | LOW | P1 |
| System prompt persona | HIGH | LOW | P1 |
| CloudWatch logs + 1 dashboard | MEDIUM | LOW | P1 |
| Graceful disconnect | MEDIUM | LOW | P1 |
| Source citation chip | MEDIUM | MEDIUM | P2 |
| Per-session cost guardrail | MEDIUM | MEDIUM | P2 (P1 if launching public URL) |
| Edge rate limit | MEDIUM | MEDIUM | P2 (P1 if launching public URL) |
| Conversation reset | MEDIUM | LOW | P2 |
| Latency telemetry (debug mode) | LOW | LOW | P2 |
| Health check + autoscaling | MEDIUM | LOW | P2 |
| Two voice options | LOW | LOW | P3 |
| Twilio | HIGH (long-term) | HIGH | P3 (v2) |
| Multi-agent router | MEDIUM (long-term) | HIGH | P3 (v2) |

### Workshop Docs

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| 5-chapter vi+en scaffold filled | HIGH | HIGH (writing) | P1 |
| Architecture diagram | HIGH | LOW | P1 |
| Prerequisites + Bedrock enable steps | HIGH | LOW | P1 |
| Hands-on with code + screenshots | HIGH | HIGH | P1 |
| Cleanup chapter + checklist | HIGH | MEDIUM | P1 |
| Cost estimate table | HIGH | LOW | P1 |
| Code copy buttons | HIGH | LOW (theme feature) | P1 |
| Language switcher works | HIGH | LOW (theme feature) | P1 |
| Troubleshooting / FAQ | MEDIUM | MEDIUM | P2 |
| Per-step verify callouts | MEDIUM | LOW | P2 |
| Glossary | MEDIUM | LOW | P2 |
| Last-verified banner | MEDIUM | LOW | P2 |
| Inline per-step cost | LOW | MEDIUM | P3 |
| Success screencast embed | MEDIUM | LOW–MEDIUM | P2 |
| Architecture deep-dive appendix | MEDIUM | MEDIUM | P2 |
| Cleanup verify script | MEDIUM | MEDIUM | P3 |
| Print-friendly export | LOW | LOW | P3 |

**Priority key:**
- P1: Must have for v1 launch (the Core Value path is broken without it)
- P2: Add in v1.x after first deploy proven and learner feedback collected
- P3: Defer; reconsider at next milestone

---

## Genre / "Competitor" Reference

This isn't a saturated commercial market, but four reference points anchor expectations:

| Feature | ElevenLabs Agents | OpenAI Realtime demo | AWS reference blog (Pipecat + Bedrock) | hera v1 |
|---------|-------------------|----------------------|----------------------------------------|---------|
| Voice transport | WebRTC | WebRTC | WebSocket (Pipecat) | WebSocket (matches AWS blog) |
| VAD / barge-in | Built-in | Built-in | Provider-handled (Sonic) | Sonic native |
| Tool calling | Yes (HTTP/webhook) | Yes (function calling) | Yes (Pipecat tools) | Yes (KB tool) |
| KB / RAG | Plug-in to provider | Manual via tools | Manual via tools | Bedrock KB native |
| Citation surfaced in UI | No | No | Optional | Differentiator (P2) |
| Web widget UX | Polished embed | Demo only | Sample HTML | Minimal but clear states (matches AWS blog spirit) |
| Source code IaC for AWS | N/A | N/A | Sample (CDK) | Terraform (workshop differentiator) |
| Bilingual workshop docs | N/A | N/A | English-only blog | vi/en (workshop differentiator) |

**Where hera differentiates:** the dual-product nature — a working AWS-native demo *plus* an FCJ-format bilingual workshop teaching learners to deploy it themselves. Neither the AWS reference blog nor commercial agent platforms ship that combination.

---

## Sources

- [PROJECT.md (hera)](file:///C:/Users/trant/projects/hera/.planning/PROJECT.md) — scope locks, anti-features already declared (Twilio, OpenSearch Serverless, n8n, mobile, Cognito, vi chatbot speech)
- [raw_content.txt (hera)](file:///C:/Users/trant/projects/hera/raw_content.txt) — verbatim Apple Store use case (Apple Watch S11, iPhone 13 Pro Max, MacBook Pro M4 stock questions); confirms the demo prompt
- [Amazon Nova 2 Sonic announcement](https://aws.amazon.com/blogs/aws/introducing-amazon-nova-2-sonic-next-generation-speech-to-speech-model-for-conversational-ai/) — confirms VAD sensitivity (high/med/low), tool use, bidirectional streaming
- [Nova Sonic barge-in docs](https://docs.aws.amazon.com/nova/latest/nova2-userguide/sonic-barge-in.html) — server-side barge-in with required client-side audio flush
- [Nova Sonic tool configuration docs](https://docs.aws.amazon.com/nova/latest/nova2-userguide/sonic-tool-configuration.html) — function calling spec
- [Migrating a text agent to Nova 2 Sonic](https://aws.amazon.com/blogs/machine-learning/migrating-a-text-agent-to-a-voice-assistant-with-amazon-nova-2-sonic/) — RAG + KB pattern with citation
- [Pipecat web & mobile transport docs](https://docs.pipecat.ai/getting-started/web-mobile) — WebSocket vs WebRTC tradeoffs
- [pipecat-examples (GitHub)](https://github.com/pipecat-ai/pipecat-examples) — Voice UI Kit, push-to-talk vs always-on patterns
- [AWS reference blog — Pipecat + Bedrock voice agents](https://aws.amazon.com/blogs/machine-learning/building-intelligent-ai-voice-agents-with-pipecat-and-amazon-bedrock-part-1/) — the hera architectural blueprint
- [Deploy voice agents with Pipecat + Bedrock AgentCore](https://aws.amazon.com/blogs/machine-learning/deploy-voice-agents-with-pipecat-and-amazon-bedrock-agentcore-runtime-part-1/) — newer deployment pattern; AgentCore noted but not adopted (ECS Fargate locked in PROJECT.md)
- [FCJ workshop catalog](https://cloudjourney.awsstudygroup.com/) — confirms FCJ format expectations (hands-on with detailed instructions and images, vi/en, cost-conscious)
- [hugo-theme-learn (Relearn) docs](https://mcshelby.github.io/hugo-theme-relearn/) — confirms theme features (copy-to-clipboard, print-friendly, multilingual, page weights)

---
*Feature research for: AWS-native voice agent demo + FCJ workshop docs*
*Researched: 2026-05-04*
