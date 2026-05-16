# Contact Flow: ~6 blocks per D-69 + 06.1-RESEARCH.md Pattern 3.
# Set Voice (Joanna Neural) -> Play Prompt greeting -> Get Customer Input
# (Lex bot alias, Interruptible=true / barge-in ON) -> Play Prompt reading
# $.Lex.SessionAttributes.answer per D-69 addendum (Pitfall 5 honored) ->
# Disconnect; error branch off Get Customer Input -> Play Prompt error ->
# Disconnect.

locals {
  greeting_text = "Welcome to Hera Apple Store. How can I help?"
  error_prompt  = "Sorry, I could not hear you. Please call back."
}

resource "aws_connect_contact_flow" "hera_voice" {
  provider = aws.us_east_1

  instance_id = aws_connect_instance.hera.id
  name        = "${var.name_prefix}-voice-flow-${var.env}"
  type        = "CONTACT_FLOW"
  description = "Hera voice channel: greet + transfer to Lex + play KB-derived answer (Phase 6.1)."

  content = templatefile("${path.module}/contact_flow/voice_flow.json.tftpl", {
    lex_bot_alias_arn = awscc_lex_bot_alias.prod.arn
    greeting_text     = local.greeting_text
    error_prompt      = local.error_prompt
  })

  depends_on = [
    awscc_lex_resource_policy.connect_invoke,
  ]
}

# Phone-to-flow binding: Terraform's aws_connect_phone_number does not yet
# natively support contact-flow target wiring on all account states (Pitfall 5).
# If the live apply leaves the DID in NO_TARGET state, the RUNBOOK Phase 6.1
# paste-flow documents the Console fallback:
#   Connect Console -> Phone numbers -> select DID -> Contact flow:
#     hera-voice-flow-prod -> Save.
# Re-running terraform apply afterwards will not drift the wiring.
