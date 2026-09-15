provider "aws" {
  region  = "us-east-1"
  profile = "academy"
}

# VPC and Subnets
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# Security Groups
resource "aws_security_group" "alb_sg" {
  name   = "alb-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
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

resource "aws_security_group" "ec2_sg" {
  name   = "ec2-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 Instances
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "app1" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  user_data              = <<-EOF
                           #!/bin/bash
                           yum install -y httpd
                           systemctl start httpd
                           systemctl enable httpd
                           mkdir -p /var/www/html/app1

                           TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
                           INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
                           AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)
                           PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
                           INSTANCE_TYPE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type)

                           cat <<HTML > /var/www/html/app1/index.html
                           <h1>App 1</h1>
                           <ul>
                             <li><strong>Instance ID:</strong> $INSTANCE_ID</li>
                             <li><strong>Availability Zone:</strong> $AZ</li>
                             <li><strong>Private IP:</strong> $PRIVATE_IP</li>
                             <li><strong>Instance Type:</strong> $INSTANCE_TYPE</li>
                           </ul>
                           HTML
                           EOF
  tags = {
    Name = "App1-Instance"
  }
}

resource "aws_instance" "app2" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_2.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  user_data              = <<-EOF
                           #!/bin/bash
                           yum install -y httpd
                           systemctl start httpd
                           systemctl enable httpd
                           mkdir -p /var/www/html/app2

                           TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
                           INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
                           AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)
                           PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
                           INSTANCE_TYPE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type)

                           cat <<HTML > /var/www/html/app2/index.html
                           <h1>App 2</h1>
                           <ul>
                             <li><strong>Instance ID:</strong> $INSTANCE_ID</li>
                             <li><strong>Availability Zone:</strong> $AZ</li>
                             <li><strong>Private IP:</strong> $PRIVATE_IP</li>
                             <li><strong>Instance Type:</strong> $INSTANCE_TYPE</li>
                           </ul>
                           HTML
                           EOF
  tags = {
    Name = "App2-Instance"
  }
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "my-alb"
  internal           = true # Set back to true since API Gateway will handle public requests
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

# Target Groups
resource "aws_lb_target_group" "app1" {
  name     = "app1-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_target_group" "app2" {
  name     = "app2-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

# Attach Instances to Target Groups
resource "aws_lb_target_group_attachment" "app1" {
  target_group_arn = aws_lb_target_group.app1.arn
  target_id        = aws_instance.app1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "app2" {
  target_group_arn = aws_lb_target_group.app2.arn
  target_id        = aws_instance.app2.id
  port             = 80
}

# ALB Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "404: Not Found"
      status_code  = "404"
    }
  }
}

# Listener Rules for Path-Based Routing
resource "aws_lb_listener_rule" "app1" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app1.arn
  }

  condition {
    path_pattern {
      values = ["/app1*"]
    }
  }
}

resource "aws_lb_listener_rule" "app2" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app2.arn
  }

  condition {
    path_pattern {
      values = ["/app2*"]
    }
  }
}

# API Gateway VPC Link (HTTP API)
# Used to securely connect an HTTP API to private resources like an internal ALB
resource "aws_apigatewayv2_vpc_link" "main" {
  name               = "my-vpc-link"
  security_group_ids = [aws_security_group.alb_sg.id]
  subnet_ids         = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

# HTTP API Gateway
resource "aws_apigatewayv2_api" "main" {
  name          = "my-http-api"
  protocol_type = "HTTP"
}

# API Gateway Integration with ALB via VPC Link
resource "aws_apigatewayv2_integration" "alb_integration" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_uri    = aws_lb_listener.http.arn
  integration_method = "ANY"
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.main.id
  
  # Proxy all requests exactly as they are to the ALB
  payload_format_version = "1.0"
}

# API Gateway Route (Catch-all)
resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.alb_integration.id}"
}

# API Gateway Stage
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true
}

# Output the API Gateway URL for easy testing
output "api_gateway_url" {
  value       = aws_apigatewayv2_stage.default.invoke_url
  description = "The public URL of the API Gateway"
}
