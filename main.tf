terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region  = var.region
  profile = var.profile
}

variable "profile" {
  type    = string
  default = "academy"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "instance_count" {
  type    = number
  default = 2
}

# ---------------------------------------------------------------
# Network: default VPC and one subnet per AZ (default VPC has 1 per AZ)
# ---------------------------------------------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_subnet" "each" {
  for_each = toset(data.aws_subnets.default.ids)
  id       = each.value
}

locals {
  # Sort subnets by AZ and take the first N so each instance lands in a different AZ
  subnets_by_az = { for s in data.aws_subnet.each : s.availability_zone => s.id }
  azs           = slice(sort(keys(local.subnets_by_az)), 0, var.instance_count)
  subnet_ids    = [for az in local.azs : local.subnets_by_az[az]]
}

# Latest Amazon Linux 2023 AMI
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ---------------------------------------------------------------
# Security groups
# ---------------------------------------------------------------
resource "aws_security_group" "alb" {
  name_prefix = "alb-demo-alb-"
  description = "Allow HTTP from the internet to the ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "web" {
  name_prefix = "alb-demo-web-"
  description = "Allow HTTP only from the ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------------------------------------------------------
# EC2 instances (one per AZ)
# ---------------------------------------------------------------
resource "aws_instance" "web" {
  count                       = var.instance_count
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.instance_type
  subnet_id                   = local.subnet_ids[count.index]
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = true # needed to reach dnf repos in the default VPC
  user_data                   = file("${path.module}/user_data.sh")

  # Re-run user data if the script changes
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required" # IMDSv2
  }

  tags = {
    Name = "alb-demo-web-${count.index + 1}"
  }
}

# ---------------------------------------------------------------
# Application Load Balancer
# ---------------------------------------------------------------
resource "aws_lb" "this" {
  name               = "alb-demo"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.subnet_ids
}

resource "aws_lb_target_group" "web" {
  name     = "alb-demo-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  # round_robin (default), least_outstanding_requests, or weighted_random
  load_balancing_algorithm_type = "round_robin"

  stickiness {
    type    = "lb_cookie"
    enabled = false
  }

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
  }
}

resource "aws_lb_target_group_attachment" "web" {
  count            = var.instance_count
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web[count.index].id
  port             = 80
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# ---------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------
output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "test_command" {
  value = ".\test.bat"
}
