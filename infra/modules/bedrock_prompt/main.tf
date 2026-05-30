# Bedrock Prompt Management — stores Hera's system prompt as a versioned,
# AWS-managed asset. The prompt text is the SAME literal that ships in
# agent/hera_agent/prompts.py; Terraform reads it from the file and extracts
# the Python triple-quoted string so the two stay in sync.
#
# Pattern: each `terraform apply` upserts a new DRAFT variant and, when the
# text has changed, publishes a new immutable version via aws_bedrockagent_prompt_version.
# The agent code remains the runtime source of truth (Sonic loads it via
# `settings.system_instruction` in pipeline.py:80); this module exists so the
# prompt is:
#   - discoverable in the AWS console under Bedrock > Prompt Management
#   - versioned with audit trail
#   - referenceable by ARN from downstream eval / orchestration jobs

locals {
  prompts_py_raw = file("${path.root}/../../../${var.system_prompt_path}")
  # Extract the SYSTEM_PROMPT = """...""" literal. The regex captures everything
  # between the first pair of triple double-quotes following SYSTEM_PROMPT = .
  system_prompt = trimspace(
    regex("SYSTEM_PROMPT\\s*=\\s*\"\"\"([\\s\\S]*?)\"\"\"", local.prompts_py_raw)[0]
  )
}

resource "aws_bedrockagent_prompt" "hera_system" {
  name        = "${var.name_prefix}-system-prompt-${var.env}"
  description = "Hera voice agent system prompt (crisp Apple Store associate persona)."

  default_variant = "v1"

  variant {
    name          = "v1"
    model_id      = var.sonic_model_id
    template_type = "TEXT"

    template_configuration {
      text {
        text = local.system_prompt
      }
    }
  }
}

# Immutable version snapshot via AWS CLI. AWS provider does not yet expose
# aws_bedrockagent_prompt_version, so we call CreatePromptVersion in a
# local-exec keyed off a hash of the prompt text. Each text change publishes a
# new version and keeps audit history.
resource "null_resource" "publish_version" {
  triggers = {
    prompt_id = aws_bedrockagent_prompt.hera_system.id
    text_hash = sha256(local.system_prompt)
  }

  provisioner "local-exec" {
    # Description has no spaces so it needs no shell quoting. On Windows,
    # Terraform runs local-exec via `cmd /C`, which strips the surrounding
    # double-quotes and splits a spaced value into multiple tokens (AWS CLI
    # then rejects them as unknown options). A hyphenated value is a single
    # token on cmd, bash, and zsh alike.
    command = "aws bedrock-agent create-prompt-version --region ${var.region} --prompt-identifier ${aws_bedrockagent_prompt.hera_system.id} --description Snapshot-at-hash-${substr(sha256(local.system_prompt), 0, 12)}"
  }
}
