resource "aws_appautoscaling_target" "api" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.api.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.min_count
  max_capacity       = var.max_count
}

# Two target tracking policies; ECS scales out on whichever needs more tasks. Requests per task
# reacts faster to a payday spike than CPU does.
resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.name}-api-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.api.service_namespace
  resource_id        = aws_appautoscaling_target.api.resource_id
  scalable_dimension = aws_appautoscaling_target.api.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = var.cpu_target_percent
    scale_out_cooldown = 60
    scale_in_cooldown  = 300
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

resource "aws_appautoscaling_policy" "requests" {
  name               = "${var.name}-api-requests"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.api.service_namespace
  resource_id        = aws_appautoscaling_target.api.resource_id
  scalable_dimension = aws_appautoscaling_target.api.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = var.requests_per_target
    scale_out_cooldown = 60
    scale_in_cooldown  = 300
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.this.arn_suffix}/${aws_lb_target_group.api.arn_suffix}"
    }
  }
}

# Payday: salaries land between the 25th and 28th (brief), so the floor is raised before the rush
# instead of waiting for target tracking to catch up. In the dev trial one task hit 100% CPU before
# new tasks were ready. Times are Lagos time. The end is 23:00 on the 28th so it also fires in
# February.
resource "aws_appautoscaling_scheduled_action" "payday_start" {
  count              = var.payday_min_count == null ? 0 : 1
  name               = "${var.name}-api-payday-start"
  service_namespace  = aws_appautoscaling_target.api.service_namespace
  resource_id        = aws_appautoscaling_target.api.resource_id
  scalable_dimension = aws_appautoscaling_target.api.scalable_dimension
  schedule           = "cron(0 6 25 * ? *)"
  timezone           = "Africa/Lagos"

  scalable_target_action {
    min_capacity = var.payday_min_count
    max_capacity = var.max_count
  }
}

resource "aws_appautoscaling_scheduled_action" "payday_end" {
  count              = var.payday_min_count == null ? 0 : 1
  name               = "${var.name}-api-payday-end"
  service_namespace  = aws_appautoscaling_target.api.service_namespace
  resource_id        = aws_appautoscaling_target.api.resource_id
  scalable_dimension = aws_appautoscaling_target.api.scalable_dimension
  schedule           = "cron(0 23 28 * ? *)"
  timezone           = "Africa/Lagos"

  scalable_target_action {
    min_capacity = var.min_count
    max_capacity = var.max_count
  }
}
