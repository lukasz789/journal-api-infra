# ------------------------------------------------------------------------------
# CloudWatch dashboard: HTTP metrics and recent application errors
# ------------------------------------------------------------------------------
# This dashboard only displays data. The agent sends metrics and Fluent Bit sends logs.
resource "aws_cloudwatch_dashboard" "journal_api" {
  dashboard_name = "${var.project_name}-api"

  dashboard_body = jsonencode({
    start          = "-PT1H"
    periodOverride = "inherit"
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "HTTP requests per minute"
          region = var.aws_region
          view   = "timeSeries"
          period = 60
          yAxis  = { left = { min = 0, label = "Requests / minute", showUnits = false } }
          metrics = [
            [{
              # SampleCount counts requests in the histogram, not their duration.
              # SEARCH finds the status-code series; SUM combines their counts.
              expression = "SUM(SEARCH('{JournalAPI, \"http.status_code\"} MetricName=\"http.server.duration\"', 'SampleCount', 60))"
              id         = "requests"
              label      = "Requests"
            }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "HTTP 5xx error percentage"
          region = var.aws_region
          view   = "timeSeries"
          period = 60
          yAxis  = { left = { min = 0, max = 100, label = "Percent", showUnits = false } }
          metrics = [
            [{
              expression = "SUM(SEARCH('{JournalAPI, \"http.status_code\"} MetricName=\"http.server.duration\"', 'SampleCount', 60))"
              id         = "requests"
              visible    = false
            }],
            [{
              # SEARCH does not accept a 5xx regex. Generate exact matches for 500-599.
              # This searches existing metrics; it does not create 100 new metrics.
              expression = "SUM(SEARCH('{JournalAPI, \"http.status_code\"} MetricName=\"http.server.duration\" (${join(" OR ", [for code in range(500, 600) : "\"${code}\""])})', 'SampleCount', 60))"
              id         = "errors"
              visible    = false
            }],
            [{
              # Show a percentage only when requests were actually observed.
              # With traffic, missing 5xx values count as zero in metric arithmetic.
              expression = "IF(requests > 0, 100 * errors / requests)"
              id         = "error_rate"
              label      = "5xx responses (%)"
            }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Average HTTP response time"
          region = var.aws_region
          view   = "timeSeries"
          period = 60
          yAxis  = { left = { min = 0, label = "Milliseconds", showUnits = false } }
          metrics = [
            [{
              expression = "SUM(SEARCH('{JournalAPI, \"http.status_code\"} MetricName=\"http.server.duration\"', 'Sum', 60))"
              id         = "duration_sum"
              visible    = false
            }],
            [{
              expression = "SUM(SEARCH('{JournalAPI, \"http.status_code\"} MetricName=\"http.server.duration\"', 'SampleCount', 60))"
              id         = "requests"
              visible    = false
            }],
            [{
              # Divide total duration by total count, not an average of status averages.
              expression = "IF(requests > 0, duration_sum / requests)"
              id         = "latency"
              label      = "Average response time (ms)"
            }]
          ]
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Recent Journal API errors"
          region = var.aws_region
          view   = "table"
          # Query CloudWatch Logs Insights for recent errors from the Journal API container.
          # Fluent Bit forwards Kubernetes container logs to the shared application log group.
          # Filter by namespace and container, then return the 20 most recent error messages.
          query = <<-QUERY
            SOURCE '/aws/containerinsights/${aws_eks_cluster.main.name}/application'
            | fields @timestamp, kubernetes.pod_name, log
            | filter kubernetes.namespace_name = 'journal-api' and kubernetes.container_name = 'journal-api'
            | filter log like /ERROR|CRITICAL|Traceback/
            | sort @timestamp desc
            | limit 20
          QUERY
        }
      },
      {
        type   = "alarm"
        x      = 0
        y      = 12
        width  = 24
        height = 3
        properties = {
          title = "HTTP 500 alarm - console only, no notifications"
          # Display this alarm's current state, not another metric graph.
          alarms = [aws_cloudwatch_metric_alarm.http_500.arn]
        }
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# HTTP 500 alarm: visible in CloudWatch, without notifications
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "http_500" {
  alarm_name        = "${var.project_name}-http-500"
  alarm_description = "3+ HTTP 500 responses per 5-minute period. Console-only alarm; no SNS notifications."

  namespace   = "JournalAPI"
  metric_name = "http.server.duration"
  # Count requests with status 500.
  statistic = "SampleCount"
  dimensions = {
    "http.status_code" = "500"
  }

  # Time window for counting HTTP 500 errors, not the duration of an error.
  # CloudWatch counts how many errors occur within each 5-minute (300s) period.
  period              = 300
  evaluation_periods  = 1
  threshold           = 3
  comparison_operator = "GreaterThanOrEqualToThreshold"

  # Treat missing data as no breach of the HTTP 500 threshold.
  treat_missing_data = "notBreaching"

  # Learning setup: state changes are visible in the console, without email or SMS.
  # A future improvement is to enable actions and send notifications through SNS.
  actions_enabled = false

  tags = {
    Name = "${var.project_name}-http-500"
  }
}
