# Connect instance — Connect free tier region us-east-1 (SPEC.md).
# Inbound voice only (no chat/task/email/outbound — SPEC out-of-scope list).
# Auto-resolve SLR per Pitfall 4 (let Connect auto-create on first instance).

resource "aws_connect_instance" "hera" {
  provider = aws.us_east_1

  instance_alias           = "${var.name_prefix}-voice-${var.env}"
  identity_management_type = "CONNECT_MANAGED"
  inbound_calls_enabled    = true
  outbound_calls_enabled   = false
}

# Claim a US DID for inbound voice. type=DID (local), country_code=US,
# description tags the demo origin. Per Pitfall 5: if first-time claim fails
# at the API level, RUNBOOK paste-flow falls back to Console claim + terraform import.
resource "aws_connect_phone_number" "us_did" {
  provider = aws.us_east_1

  target_arn   = aws_connect_instance.hera.arn
  country_code = "US"
  type         = "DID"
  description  = "Hera demo inbound voice number (Phase 6.1)"
}
