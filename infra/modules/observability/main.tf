# Observability: CloudWatch dashboard + operational alarms (OBS-01..03)
# + billing alarm (OBS-05 best-effort, declared further down).
#
# D-13: zero new IAM roles/wildcards (dashboards are read-only via caller IAM).
# D-29: billing threshold = $5/day verbatim (banner copy hardcode).
# D-35: alarm_actions = [] -- no SNS, no Lambda. Dashboard-visible only.
#
# Cross-region provider alias: AWS/Billing EstimatedCharges is only emitted
# in us-east-1, so the billing alarm uses provider = aws.us_east_1 passed
# in via the module's `providers` map.

# --- Dashboard ---
resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "${var.name_prefix}-${var.env}"

  dashboard_body = jsonencode({
    widgets = [
      # 1. Active sessions (singleValue, 1-min sum) — top-left.
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 6
        height = 6
        properties = {
          title = "Active sessions (1-min sum)"
          metrics = [
            ["AWS/Bedrock-AgentCore", "ActiveStreamingConnections",
            "Resource", var.agentcore_runtime_arn]
          ]
          view   = "singleValue"
          stat   = "Sum"
          period = 60
          region = var.region
        }
      },
      # 2. Latency p50 / p95 (timeSeries) — top-right.
      {
        type   = "metric"
        x      = 6
        y      = 0
        width  = 12
        height = 6
        properties = {
          title = "Latency p50 / p95"
          metrics = [
            ["AWS/Bedrock-AgentCore", "Latency", "Resource", var.agentcore_runtime_arn,
            { stat = "p50", label = "p50" }],
            ["AWS/Bedrock-AgentCore", "Latency", "Resource", var.agentcore_runtime_arn,
            { stat = "p95", label = "p95" }]
          ]
          view   = "timeSeries"
          period = 60
          region = var.region
        }
      },
      # 3. Error rate (timeSeries with arithmetic).
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title = "Error rate (TotalErrors / Invocations)"
          metrics = [
            [{ expression = "IF(m1>0, 100*m2/m1, 0)", label = "Error rate %", id = "e1" }],
            ["AWS/Bedrock-AgentCore", "Invocations", "Resource", var.agentcore_runtime_arn,
            { id = "m1", visible = false, stat = "Sum" }],
            ["AWS/Bedrock-AgentCore", "TotalErrors", "Resource", var.agentcore_runtime_arn,
            { id = "m2", visible = false, stat = "Sum" }]
          ]
          view   = "timeSeries"
          period = 60
          region = var.region
        }
      },
      # 4. Bedrock invocations + token volume (timeSeries) — cost proxy.
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title = "Bedrock invocations + token volume"
          metrics = [
            ["AWS/Bedrock", "Invocations", "ModelId", var.sonic_model_id],
            ["AWS/Bedrock", "InputTokenCount", "ModelId", var.sonic_model_id],
            ["AWS/Bedrock", "OutputTokenCount", "ModelId", var.sonic_model_id]
          ]
          view   = "timeSeries"
          period = 300
          region = var.region
        }
      },
      # 5. Estimated charges (cross-region, us-east-1).
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 24
        height = 6
        properties = {
          title = "Estimated charges (USD, us-east-1, AWS/Billing)"
          metrics = [
            ["AWS/Billing", "EstimatedCharges", "Currency", "USD"]
          ]
          view   = "timeSeries"
          stat   = "Maximum"
          period = 21600
          region = "us-east-1"
        }
      }
    ]
  })
}

# --- Operational alarm: error rate >5% over 5 min (metric_query arithmetic) ---
resource "aws_cloudwatch_metric_alarm" "error_rate" {
  alarm_name          = "${var.name_prefix}-error-rate-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = var.error_rate_threshold_pct
  alarm_description   = "AgentCore error rate > ${var.error_rate_threshold_pct}% over 5 minutes"
  treat_missing_data  = "notBreaching"
  alarm_actions       = []

  metric_query {
    id          = "e1"
    expression  = "IF(m1 > 0, 100*m2/m1, 0)"
    label       = "Error rate %"
    return_data = true
  }
  metric_query {
    id = "m1"
    metric {
      metric_name = "Invocations"
      namespace   = "AWS/Bedrock-AgentCore"
      period      = 300
      stat        = "Sum"
      dimensions  = { Resource = var.agentcore_runtime_arn }
    }
  }
  metric_query {
    id = "m2"
    metric {
      metric_name = "TotalErrors"
      namespace   = "AWS/Bedrock-AgentCore"
      period      = 300
      stat        = "Sum"
      dimensions  = { Resource = var.agentcore_runtime_arn }
    }
  }
}

# --- Operational alarm: latency p95 >5s over 5 min (extended_statistic) ---
resource "aws_cloudwatch_metric_alarm" "latency_p95" {
  alarm_name          = "${var.name_prefix}-latency-p95-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = var.latency_p95_threshold_ms
  alarm_description   = "AgentCore p95 latency > ${var.latency_p95_threshold_ms}ms over 5 minutes"
  treat_missing_data  = "notBreaching"
  alarm_actions       = []

  metric_name        = "Latency"
  namespace          = "AWS/Bedrock-AgentCore"
  period             = 300
  extended_statistic = "p95"
  dimensions         = { Resource = var.agentcore_runtime_arn }
}
