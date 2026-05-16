# Lex V2 6-resource layout per D-68 addendum + 06.1-RESEARCH.md Pattern 1.
# Replaces the missing aws_lexv2models_bot_alias (gh#35780) and the V1-only
# aws_connect_bot_association (gh#30869) with awscc_lex_bot_alias +
# awscc_lex_resource_policy. Pitfalls 1+2+3 honored via depends_on +
# condition blocks.

resource "aws_lexv2models_bot" "product_lookup" {
  provider = aws.us_east_1

  name                        = "${var.name_prefix}-product-lookup-${var.env}"
  role_arn                    = aws_iam_role.lex_service.arn
  idle_session_ttl_in_seconds = 300

  data_privacy {
    child_directed = false
  }
}

resource "aws_lexv2models_bot_locale" "en_us" {
  provider = aws.us_east_1

  bot_id                           = aws_lexv2models_bot.product_lookup.id
  bot_version                      = "DRAFT"
  locale_id                        = "en_US"
  n_lu_intent_confidence_threshold = 0.40

  voice_settings {
    voice_id = "Joanna"
    engine   = "neural"
  }
}

resource "aws_lexv2models_intent" "fallback" {
  provider = aws.us_east_1

  bot_id                  = aws_lexv2models_bot.product_lookup.id
  bot_version             = aws_lexv2models_bot_locale.en_us.bot_version
  locale_id               = aws_lexv2models_bot_locale.en_us.locale_id
  name                    = "FallbackIntent"
  parent_intent_signature = "AMAZON.FallbackIntent"

  fulfillment_code_hook {
    enabled = true
  }
}

# Lex V2 build requires at least one CUSTOM intent with utterances; built-in
# FallbackIntent alone makes `aws lexv2-models build-bot-locale` fail with
# "The locale 'en_US' doesn't have any utterances". This custom intent catches
# generic product inquiry phrasings; the same Lambda fulfillment runs whether
# this intent or FallbackIntent matches (handler reads event.inputTranscript,
# not slot values), so the answer pipeline is identical.
resource "aws_lexv2models_intent" "product_inquiry" {
  provider = aws.us_east_1

  bot_id      = aws_lexv2models_bot.product_lookup.id
  bot_version = aws_lexv2models_bot_locale.en_us.bot_version
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id
  name        = "ProductInquiry"

  sample_utterance {
    utterance = "do you have it in stock"
  }
  sample_utterance {
    utterance = "is it available"
  }
  sample_utterance {
    utterance = "tell me about a product"
  }
  sample_utterance {
    utterance = "I have a question about a product"
  }

  fulfillment_code_hook {
    enabled = true
  }
}

# Pitfall 1: Lex builds the locale at version-create time. Intent must exist first.
# Terraform data-flow doesn't detect this; explicit depends_on required.
resource "aws_lexv2models_bot_version" "v1" {
  provider = aws.us_east_1

  bot_id = aws_lexv2models_bot.product_lookup.id

  locale_specification = {
    (aws_lexv2models_bot_locale.en_us.locale_id) = {
      source_bot_version = "DRAFT"
    }
  }

  depends_on = [
    aws_lexv2models_intent.fallback,
    aws_lexv2models_intent.product_inquiry,
  ]
}

# Pitfall 2: alias references the Lambda ARN at create time. Cross-provider
# data-flow detection is unreliable; explicit depends_on enforces ordering.
resource "awscc_lex_bot_alias" "prod" {
  provider = awscc.us_east_1

  bot_alias_name = "prod"
  bot_id         = aws_lexv2models_bot.product_lookup.id
  bot_version    = aws_lexv2models_bot_version.v1.bot_version

  bot_alias_locale_settings = [{
    locale_id = aws_lexv2models_bot_locale.en_us.locale_id
    bot_alias_locale_setting = {
      enabled = true
      code_hook_specification = {
        lambda_code_hook = {
          lambda_arn                  = aws_lambda_function.lookup.arn
          code_hook_interface_version = "1.0"
        }
      }
    }
  }]

  sentiment_analysis_settings = {
    detect_sentiment = false
  }

  depends_on = [
    aws_lambda_function.lookup,
    aws_lambda_permission.lex_invoke,
  ]
}

# Replaces aws_connect_bot_association (Lex V1 only). Grants Connect runtime
# access to invoke the alias. Per Pitfall 3, BOTH AWS:SourceAccount AND
# AWS:SourceArn conditions are required for service-principal policies.
resource "awscc_lex_resource_policy" "connect_invoke" {
  provider = awscc.us_east_1

  resource_arn = awscc_lex_bot_alias.prod.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowConnectInvokeLexV2"
      Effect = "Allow"
      Principal = {
        Service = "connect.amazonaws.com"
      }
      Action = [
        "lex:RecognizeText",
        "lex:RecognizeUtterance",
        "lex:StartConversation",
        "lex:DeleteSession",
        "lex:GetSession",
        "lex:PutSession",
      ]
      Resource = [awscc_lex_bot_alias.prod.arn]
      Condition = {
        StringEquals = {
          "AWS:SourceAccount" = var.account_id
        }
        ArnEquals = {
          "AWS:SourceArn" = aws_connect_instance.hera.arn
        }
      }
    }]
  })
}
