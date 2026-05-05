terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.27"
    }
  }
  # No backend block — local state for v1 (D-11). See RUNBOOK "Next steps (deferred)" for remote backend migration.
}
