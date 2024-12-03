locals {
  user_data = <<-EOF
#!/bin/bash -e

apt update
apt install docker.io unzip -y

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

export ELIXIR_ERL_OPTIONS="+fnu"
export NB_USER=${var.nb_users}

${var.neurow_config}

docker run --rm -d \
  --net=host \
  --ulimit nofile=262144 \
  -e ELIXIR_ERL_OPTIONS \
  -e ELIXIR_ERL_OPTIONS \
  -e PUBLISH_JWT_AUDIENCE \
  -e SSE_JWT_AUDIENCE \
  -e SSE_USER_AGENT \
  -e SSE_JWT_SECRET \
  -e SSE_JWT_ISSUER \
  -e PUBLISH_JWT_SECRET \
  -e PUBLISH_JWT_ISSUER \
  -e PUBLISH_URL \
  -e SSE_URL \
  -e DELAY_BETWEEN_MESSAGES_MIN \
  -e DELAY_BETWEEN_MESSAGES_MAX \
  -e NUMBER_OF_MESSAGES_MIN \
  -e NUMBER_OF_MESSAGES_MAX \
  -e SSE_AUTO_RECONNECT \
  -e SSE_TIMEOUT \
  -e INITIAL_DELAY_MAX \
  -e PUBLISH_HTTP_POOL_SIZE \
  -e NB_USER \
  ${var.neurow_load_test_image}

aws secretsmanager get-secret-value --region="${var.region}" --secret-id=${var.dd_secret_arn} | jq -r .SecretString > /tmp/secret

DD_API_KEY="$(cat /tmp/secret)" DD_HOST_TAGS="${var.dd_tags}" bash -c "$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script_agent7.sh)"

echo "instances:
  - prometheus_url: http://localhost:2999/metrics
    namespace: neurow_load_test
    metrics:
    - messages
    - user_running
    - users
    - propagation_delay_sum
    - propagation_delay_count
    - memory_usage
    - reconnect
    - erlang_vm_memory_atom_bytes_total
    - erlang_vm_memory_bytes_total
    - erlang_vm_memory_dets_tables
    - erlang_vm_memory_ets_tables
    - erlang_vm_memory_processes_bytes_total
    - erlang_vm_memory_system_bytes_total
    - erlang_vm_process_count
" >> /etc/datadog-agent/conf.d/prometheus.d/conf.yaml
service datadog-agent restart
EOF
}

resource "aws_iam_instance_profile" "neurow_load_test" {
  name = "${var.resource_prefix}-load-test"
  role = aws_iam_role.neurow_load_test.name
}

resource "aws_iam_role" "neurow_load_test" {
  name = "${var.resource_prefix}-load-test"
  path = "/"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
               "Service": "ec2.amazonaws.com"
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "neurow_load_test_ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.neurow_load_test.name
}

resource "aws_iam_role_policy_attachment" "neurow_load_test_policy" {
  policy_arn = aws_iam_policy.neurow_load_test_policy.arn
  role       = aws_iam_role.neurow_load_test.name
}

resource "aws_iam_policy" "neurow_load_test_policy" {
  name = "${var.resource_prefix}-load-test-policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    ${var.extended_policy}
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "${var.dd_secret_arn}"
    }
  ]
}
EOF
}

resource "aws_launch_template" "neurow_load_test" {
  name = "${var.resource_prefix}-load-test"

  ebs_optimized = true

  iam_instance_profile {
    name = aws_iam_instance_profile.neurow_load_test.name
  }

  image_id = data.aws_ami.ami-x86.id

  instance_initiated_shutdown_behavior = "terminate"

  instance_type = var.instance_type

  monitoring {
    enabled = true
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.neurow_load_test.id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.resource_prefix}-load-test"
    }
  }

  user_data = base64encode(local.user_data)
}

resource "aws_security_group" "neurow_load_test" {
  name   = "${var.resource_prefix}-load-test"
  vpc_id = data.aws_subnet.first_public.vpc_id
}

resource "aws_security_group_rule" "neurow_load_test_outbound" {
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.neurow_load_test.id
}

resource "aws_security_group_rule" "neurow_load_test_inbound_lb" {
  type                     = "ingress"
  from_port                = 2999
  to_port                  = 2999
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.internal_lb.id
  security_group_id        = aws_security_group.neurow_load_test.id
}

resource "aws_security_group_rule" "neurow_load_test_inbound_self" {
  type                     = "ingress"
  from_port                = 2999
  to_port                  = 2999
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.neurow_load_test.id
  security_group_id        = aws_security_group.neurow_load_test.id
}

resource "aws_autoscaling_group" "neurow_load_test" {
  name             = "${var.resource_prefix}-load-test"
  desired_capacity = var.desired_capacity
  max_size         = var.max_size
  min_size         = var.min_size

  vpc_zone_identifier = var.public_subnet_ids

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  launch_template {
    id      = aws_launch_template.neurow_load_test.id
    version = aws_launch_template.neurow_load_test.latest_version
  }

  target_group_arns = [aws_lb_target_group.internal.arn]

  health_check_type = "ELB"
}