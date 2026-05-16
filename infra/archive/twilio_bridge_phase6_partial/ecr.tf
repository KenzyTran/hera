# Private ECR repo for the multi-arch hera-twilio-bridge container image.
#
# Tag mutability locked to IMMUTABLE — git-SHA tags only; mirrors
# infra/modules/ecr (Plan 03-01 D-25 contract).
#
# force_delete = true per D-63: bridge ECR is short-lived/re-creatable;
# cleanup quy trinh in Plan 06-03 RUNBOOK runs `terraform destroy` and the
# repo MUST drop cleanly even with images present. The agent ECR (Phase 3)
# uses force_delete=false because the agent image rollback path matters;
# the bridge image has no rollback contract — it is rebuilt from `feat()`
# commits during the next deploy.

resource "aws_ecr_repository" "bridge" {
  name                 = "${var.name_prefix}-twilio-bridge"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "bridge" {
  repository = aws_ecr_repository.bridge.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last ${var.keep_last_n_untagged} untagged images"
      selection = {
        tagStatus   = "untagged"
        countType   = "imageCountMoreThan"
        countNumber = var.keep_last_n_untagged
      }
      action = {
        type = "expire"
      }
    }]
  })
}
