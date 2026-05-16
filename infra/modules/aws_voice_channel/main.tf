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

# Phone number claim DEFERRED (Plan 06.1-03 live blocker, 2026-05-16).
#
# Both API (`aws connect claim-phone-number`) and Console (Instance Admin UI ->
# Phone numbers -> Claim a number) returned identical false-positive error:
#   Status: FAILED
#   Message: "The allowed limit for claimed phone numbers has been exceeded for
#            your instance"
# despite quota (5 phone numbers per instance) and 0 phones actually claimed
# account-wide (`aws connect list-phone-numbers-v2` returns []).
#
# Root cause (suspected): new Connect tenant eligibility gate. Fresh AWS
# accounts in us-east-1 hit this hidden warm-up requirement for Toll-free AND
# DID claims; AWS Support ticket is the documented unblock path.
#
# AWS-NAT-01 partial-close (instance live, DID deferred). AWS-NAT-05 deferred
# until phone number unblock. AWS-NAT-02..04 + AWS-NAT-06 close in this plan.
#
# To re-enable after support ticket resolves: uncomment resource below, then
# either run terraform apply (auto-claims via API path) OR claim via Console
# and terraform import (Pitfall 5 fallback pattern).
#
# resource "aws_connect_phone_number" "us_did" {
#   provider = aws.us_east_1
#
#   target_arn   = aws_connect_instance.hera.arn
#   country_code = "US"
#   type         = "TOLL_FREE"
#   description  = "Hera demo inbound voice (Phase 6.1)"
# }
