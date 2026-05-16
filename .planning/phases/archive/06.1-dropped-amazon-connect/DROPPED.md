# Phase 6.1 — DROPPED Archive

**Dropped:** 2026-05-16
**Phase context:** v2.0 Milestone — Phase 6.1 (Native AWS Voice Channel — Amazon Connect)
**Status:** Phase live-deployed (15/16 resources), then dropped by user decision; live AWS state torn down; module + root TF refs removed.

## What this was

Phase 6.1 superseded Phase 6 (Twilio bridge — D-56 App Runner WSS limit) by routing PSTN voice through native AWS: Amazon Connect → Contact Flow → Lex V2 bot → Lookup Lambda → Bedrock KB cross-region → Polly Neural Joanna response.

Live deploy on 2026-05-16 stood up 15 resources successfully:
- Amazon Connect instance `hera-voice-prod` (us-east-1)
- Lex V2 bot `hera-product-lookup-prod` with FallbackIntent + ProductInquiry
- Lookup Lambda `hera-voice-lookup-prod` (Python 3.13)
- Contact Flow `hera-voice-flow-prod` (PUBLISHED, Polly Neural Joanna)
- Lex bot alias `prod` + Lex resource policy (Connect invoke)
- IAM Lex service role + Lambda exec role + permissions

Phone number was blocked at AWS new-account eligibility level (false-positive "limit exceeded" from both API and Console claim, with 0 phones actually claimed account-wide) — would have required 1-2 business day AWS Support ticket.

## Why it was dropped

User decision (2026-05-16) after live deploy + Lex Console test:

1. **Newer technology preferred**: v1 voice path uses Bedrock Nova 2 Sonic (1 foundation model end-to-end speech-to-speech with barge-in / sub-2s latency). Phase 6.1 stack used older IVR-style architecture (Lex V2 ASR + Lambda + Polly TTS multi-component pipeline with 3-5s gaps, no barge-in).
2. **Simpler architecture**: only one voice bot needed for the demo workshop; running both creates confusion about which is canonical.
3. **Phone number blocker**: even if AWS Support unblocked the claim, the voice quality and UX wouldn't match the v1 Nova Sonic experience.
4. **Demo budget**: AgentCore Runtime + Pipecat + Nova Sonic was already deployed and working at the IaC layer; running Phase 6.1 stack in parallel was duplicate AWS cost (Connect instance ~$0/hr idle but phone number ~$1/mo recurring after unblock).

## What was correct (preserved in commit history for reference)

- **`infra/modules/aws_voice_channel/lex.tf`** — Lex V2 6-resource layout: aws_lexv2models_bot + bot_locale + intent (FallbackIntent imported from auto-create) + bot_version + awscc_lex_bot_alias + awscc_lex_resource_policy. The `awscc` provider gap-fill for missing `aws_lexv2models_bot_alias` (hashicorp/aws gh#35780) is a reusable pattern.
- **`infra/modules/aws_voice_channel/lambda/handler.py`** — Lex V2 fulfillment Lambda calling bedrock-agent-runtime:Retrieve cross-region. Pattern reusable for any cross-region KB consumer.
- **`infra/modules/aws_voice_channel/contact_flow/voice_flow.json.tftpl`** — Contact Flow JSON template with `ConnectParticipantWithLexBot` requiring THREE error transitions (InputTimeLimitExceeded + NoMatchingCondition + NoMatchingError). The empty-error-body InvalidContactFlowException debugging trick (`aws --cli-error-format json connect create-contact-flow ...`) is preserved in 06.1-03-SUMMARY.md.
- **D-70 KB consumer policy reuse** — Lambda role attached existing `hera-kb-retrieve-prod` instead of creating new KB IAM. Pattern preserved for any future cross-region KB consumer.

These artifacts are findable via `git log --follow infra/archive/...` or `git log --all -- infra/modules/aws_voice_channel/`.

## What was wrong (lessons for re-pivot)

- **Phone number claim eligibility gate** is an undocumented AWS new-account requirement for fresh Connect tenants. Both API and Console claim return false-positive "limit exceeded" with 0 phones actually claimed account-wide. Only AWS Support ticket resolves it.
- **FallbackIntent built-in** is auto-created by Lex V2 when `aws_lexv2models_bot_locale` is created. Terraform `aws_lexv2models_intent` with name=FallbackIntent fails with "Intent with name FallbackIntent already exists" on first apply. Fix: `terraform import 'module.aws_voice_channel.aws_lexv2models_intent.fallback' 'FALLBCKINT:<BOT_ID>:DRAFT:en_US'` (intent ID is literal `FALLBCKINT`).
- **Lex V2 build requires CUSTOM intent** with utterances — built-in FallbackIntent alone causes locale build to fail with "The locale 'en_US' doesn't have any utterances". Adding a stub `ProductInquiry` intent with sample utterances unblocks build.
- **Contact Flow `ConnectParticipantWithLexBot` requires 3 error transitions**: InputTimeLimitExceeded + NoMatchingCondition + NoMatchingError. AWS Connect API returns empty-body InvalidContactFlowException on missing any one; `aws --cli-error-format json` surfaces the diagnostic.

## Re-pivot pointers (if v3+ ever revisits PSTN voice)

If PSTN voice channel is revisited:
- Operator must submit AWS Support ticket FIRST to enable phone number claim (1-2 business days)
- Phase 6.1 IaC (in git history) is portable; uncomment the `aws_connect_phone_number.us_did` resource block in main.tf after support unblock
- Consider Connect Contact Lens for transcript/sentiment (out-of-scope here)
- Consider Connect Tasks API instead of Voice for async demo path (avoid PSTN entirely)

v2.0 milestone effectively cancelled. v1 (Phase 1-5) remains the sole production path: web widget → AgentCore Runtime → Pipecat → Nova 2 Sonic → KB.
