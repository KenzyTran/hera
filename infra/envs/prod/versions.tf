terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.27"
    }
    # D-68 addendum: hashicorp/aws 6.45 does NOT ship aws_lexv2models_bot_alias
    # (gh#35780) and aws_connect_bot_association is Lex V1 only (V1 EOL
    # 2025-09-15, gh#30869). awscc fills both gaps via awscc_lex_bot_alias
    # + awscc_lex_resource_policy. Phase 6.1 Plan 06.1-02 introduces this pin.
    awscc = {
      source  = "hashicorp/awscc"
      version = "~> 1.84"
    }
  }
  # No backend block — local state for v1 (D-11). See RUNBOOK "Next steps (deferred)" for remote backend migration.
}
