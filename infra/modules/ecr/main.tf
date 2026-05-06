# Private ECR repo for the multi-arch hera-agent container image.
#
# Tag mutability locked to IMMUTABLE — precludes a mutable :latest tag; D-25
# is satisfied with git-SHA tags only. Plan 03-03 push script must NOT pass
# -t :latest -- the second push of the same tag would fail with
# ImageTagAlreadyExistsException, which is the intended D-25 behavior.
#
# force_delete = false because terraform destroy of an ECR repo with images
# in it would silently nuke the image history. The documented destroy path
# is `aws ecr delete-repository --force` from the operator (Phase 4 cleanup
# script). Defaulting to true here would be a footgun.

resource "aws_ecr_repository" "hera_agent" {
  name                 = var.name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "hera_agent" {
  repository = aws_ecr_repository.hera_agent.name

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
