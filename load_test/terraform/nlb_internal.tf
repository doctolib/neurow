resource "aws_security_group" "internal_lb" {
  name   = "${var.resource_prefix}-lb-load-test"
  vpc_id = data.aws_subnet.first_public.vpc_id
}

resource "aws_security_group_rule" "internal_lb_outbound" {
  type              = "egress"
  from_port         = 2999
  to_port           = 2999
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.internal_lb.id
}

resource "aws_lb" "internal" {
  name               = "${var.resource_prefix}-load-test"
  internal           = true
  load_balancer_type = "network"

  subnets         = var.public_subnet_ids
  security_groups = [aws_security_group.internal_lb.id]

  enable_cross_zone_load_balancing = false
}

resource "aws_lb_listener" "internal" {
  load_balancer_arn = aws_lb.internal.arn
  port              = "2999"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.internal.arn
  }
}

resource "aws_lb_target_group" "internal" {
  name     = "${var.resource_prefix}-load-test"
  port     = 2999
  protocol = "TCP"
  vpc_id   = data.aws_subnet.first_public.vpc_id

  health_check {
    path     = "/metrics"
    port     = 2999
    protocol = "HTTP"
    interval = 10
  }
}