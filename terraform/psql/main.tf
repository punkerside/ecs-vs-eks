resource "aws_iam_role" "main" {
  name               = "${var.name}-psql"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": ["ecs.amazonaws.com", "ecs-tasks.amazonaws.com"]
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  tags = {
    Name = "${var.name}-psql"
  }
}

resource "aws_iam_role_policy" "main" {
  name = "${var.name}-psql"
  role = aws_iam_role.main.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:*",
        "ecs:*",
        "ecr:*",
        "ec2:*",
        "acm:*",
        "logs:*"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_ecs_cluster" "main" {
  name = "${var.name}-psql"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = {
    Name = "${var.name}-psql"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

resource "aws_ecs_task_definition" "main" {
  family                   = "${var.name}-psql"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.main.arn

  container_definitions    = jsonencode([
    {
      name      = "${var.name}-psql"
      image     = "${data.aws_caller_identity.main.account_id}.dkr.ecr.${data.aws_region.main.name}.amazonaws.com/${var.name}:psql"
      cpu       = 256
      memory    = 512
      essential = true
      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
        }
      ]
      environment = [
        {
          name = "DB_HOSTNAME"
          value = data.aws_db_instance.main.address
        }
      ]
    }
  ])
}

resource "aws_security_group" "main" {
  name        = "${var.name}-psql"
  description = "inbound traffic"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-psql"
  }
}