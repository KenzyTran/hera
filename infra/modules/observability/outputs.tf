output "dashboard_name" {
  description = "Dashboard name (D-12 fixed: hera-prod)."
  value       = aws_cloudwatch_dashboard.this.dashboard_name
}

output "dashboard_url" {
  description = "AWS console URL for the Phase 4 CloudWatch dashboard. RUNBOOK Phase 4 dashboard walkthrough section embeds this."
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.this.dashboard_name}"
}

output "error_rate_alarm_name" {
  description = "Operational alarm: error rate >5% / 5 min."
  value       = aws_cloudwatch_metric_alarm.error_rate.alarm_name
}

output "latency_p95_alarm_name" {
  description = "Operational alarm: latency p95 >5s / 5 min."
  value       = aws_cloudwatch_metric_alarm.latency_p95.alarm_name
}

output "billing_alarm_arn" {
  description = "us-east-1 billing alarm ARN. Phase 5 workshop content references for screenshot."
  value       = aws_cloudwatch_metric_alarm.billing.arn
}
