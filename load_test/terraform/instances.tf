locals {
  user_data = <<-EOF
#!/bin/bash -e

yum install -y ncurses-compat-libs git jq htop gcc gcc-c++
wget https://binaries2.erlang-solutions.com/centos/7/esl-erlang_26.2.1_1~centos~7_x86_64.rpm -O /tmp/esl-erlang_26.2.1_1~centos~7_x86_64.rpm
rpm -ivh /tmp/esl-erlang_26.2.1_1~centos~7_x86_64.rpm

wget https://github.com/elixir-lang/elixir/releases/download/v1.17.2/elixir-otp-26.zip -O /tmp/elixir-otp-26.zip
mkdir /opt/elixir
cd /opt/elixir
unzip /tmp/elixir-otp-26.zip

export PATH=/opt/elixir/bin:$PATH
export ELIXIR_ERL_OPTIONS="+fnu"
export HOME=/opt/home

mkdir $HOME

cd /opt
git clone https://github.com/doctolib/neurow.git
cd neurow
git checkout ${var.neurow_revision}
cd load_test

mix local.hex --force
mix deps.get

MIX_ENV=prod mix release

ulimit -n 1000000

${var.neurow_config}

export NB_USER=${var.nb_users}
export RELEASE_TMP=/tmp/
export RUN_ERL_LOG_MAXSIZE=1000000000

_build/prod/rel/load_test/bin/load_test daemon

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

  health_check_type = "EC2"
}