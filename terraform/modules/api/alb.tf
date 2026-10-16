resource "aws_lb" "this" {
  #checkov:skip=CKV_AWS_91:Access logs need a separate bucket; WAF metrics and app logs cover request tracing for now. Recommended for prod in the design document
  #checkov:skip=CKV_AWS_150:Every environment is destroyed after each session (assessment rule R5); deletion protection would block terraform destroy
  #checkov:skip=CKV2_AWS_76:False positive: the attached WAF uses AWSManagedRulesKnownBadInputsRuleSet (Log4j) through a dynamic block Checkov does not expand
  name               = var.name
  load_balancer_type = "application"
  internal           = false
  subnets            = var.public_subnet_ids
  security_groups    = [var.alb_security_group_id]
  # Rejects requests with malformed headers instead of passing them to the app.
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "api" {
  name        = "${var.name}-api"
  port        = var.app_port
  protocol    = "HTTP"
  target_type = "ip" # Fargate tasks register by IP address
  vpc_id      = var.vpc_id
  # Give in-flight requests 30 seconds to finish when a task is replaced.
  deregistration_delay = 30

  # Liveness only. /health (which also checks the database) is for monitoring, not for routing.
  health_check {
    path                = "/health/live"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
  }
}

# HTTP only redirects. Nothing is ever served over plain HTTP (brief item 6.3).
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      protocol    = "HTTPS"
      port        = "443"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  # TLS 1.3, plus TLS 1.2 with forward secret AES-GCM ciphers only ("Res" = restricted).
  # One of the policies Security Hub control ELB.17 accepts.
  ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"
  certificate_arn = local.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}
