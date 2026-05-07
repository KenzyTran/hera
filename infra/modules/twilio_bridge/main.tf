# Hera Twilio Bridge App Runner service (Phase 6 — D-56 REVISED).
#
# Long-running Python FastAPI container (Plan 06-02 ships the source) that:
#   - terminates the Twilio Media Streams WebSocket at /twilio
#   - validates X-Twilio-Signature HMAC at the WS upgrade (D-67)
#   - opens a SigV4-signed upstream WSS to bedrock-agentcore for the call
#   - bidirectionally bridges resampled audio (mu-law 8kHz <-> Int16 16kHz)
#
# min_size = 0 (D-56) -> $0/mo idle, scale-to-zero. max_size = 2 (D-65)
# capped to AgentCore concurrency cap=2 (D-30) so the bridge cannot fan out
# beyond what AgentCore accepts. Bridge cold start (~1-3s) is acceptable
# given Twilio's TCP/TLS handshake tolerance + the upstream WSS open
# happens AFTER Twilio's `start` event (off the call-pickup latency budget).
#
# Chicken-and-egg: image_tag = "" -> public placeholder image so the FIRST
# `terraform apply` succeeds before the bridge image is pushed to ECR
# (Pattern S10). Plan 06-03 second-pass apply pins the real SHA. Mirrors
# widget_presigner's agentcore_runtime_arn lifecycle from Phase 3.

locals {
  # On first apply (image_tag == "") use a public placeholder image so
  # App Runner can boot before bin/push-bridge-image.sh lands the bridge
  # container. ECR_PUBLIC type matches `public.ecr.aws/...` identifiers;
  # ECR (private) matches the bridge repo URL once an image is pushed.
  image_identifier = (var.image_tag == ""
    ? "public.ecr.aws/aws-containers/hello-app-runner:latest"
  : "${aws_ecr_repository.bridge.repository_url}:${var.image_tag}")
  image_repository_type = (var.image_tag == "" ? "ECR_PUBLIC" : "ECR")
}

resource "aws_apprunner_auto_scaling_configuration_version" "bridge_asc" {
  auto_scaling_configuration_name = local.asc_name
  max_concurrency                 = var.max_concurrency
  max_size                        = var.max_size
  min_size                        = var.min_size
}

resource "aws_apprunner_service" "bridge" {
  service_name = local.service_name

  instance_configuration {
    cpu               = var.cpu
    memory            = var.memory
    instance_role_arn = aws_iam_role.bridge_instance.arn
  }

  source_configuration {
    auto_deployments_enabled = false

    # access_role_arn is required for ECR (private) and ignored for
    # ECR_PUBLIC. Always passing it is the simplest deterministic shape;
    # AWS provider accepts it on ECR_PUBLIC without complaint.
    authentication_configuration {
      access_role_arn = aws_iam_role.bridge_access.arn
    }

    image_repository {
      image_identifier      = local.image_identifier
      image_repository_type = local.image_repository_type

      image_configuration {
        port = "8080"
        runtime_environment_variables = {
          AWS_REGION            = var.region
          AGENTCORE_RUNTIME_ARN = var.agentcore_runtime_arn
        }
        runtime_environment_secrets = {
          TWILIO_AUTH_TOKEN = var.twilio_auth_token_secret_arn
        }
      }
    }
  }

  network_configuration {
    ingress_configuration {
      is_publicly_accessible = true
    }
    egress_configuration {
      egress_type = "DEFAULT"
    }
  }

  auto_scaling_configuration_arn = aws_apprunner_auto_scaling_configuration_version.bridge_asc.arn

  health_check_configuration {
    protocol            = "HTTP"
    path                = "/ping"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 1
    unhealthy_threshold = 5
  }

  observability_configuration {
    observability_enabled = false
  }

  depends_on = [
    aws_iam_role_policy.bridge_instance_inline,
    aws_iam_role_policy.bridge_access_inline,
    aws_cloudwatch_log_group.bridge,
  ]
}
