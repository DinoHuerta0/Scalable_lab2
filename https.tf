# ---------------------------------------------------------------
# HTTPS for the demo using a SELF-SIGNED certificate.
#
# ACM cannot issue a public certificate for the *.elb.amazonaws.com
# name, so for a demo without a domain we generate a self-signed
# certificate and import it into ACM. Browsers will show a
# "not secure" warning; that is expected. curl needs the -k flag.
#
# For a trusted certificate, use your own domain and an
# aws_acm_certificate with DNS validation instead (see README).
# ---------------------------------------------------------------

resource "tls_private_key" "demo" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "demo" {
  private_key_pem = tls_private_key.demo.private_key_pem

  subject {
    common_name  = aws_lb.this.dns_name
    organization = "ALB Demo"
  }

  dns_names             = [aws_lb.this.dns_name]
  validity_period_hours = 720 # 30 days
  allowed_uses          = ["key_encipherment", "digital_signature", "server_auth"]
}

resource "aws_acm_certificate" "demo" {
  private_key      = tls_private_key.demo.private_key_pem
  certificate_body = tls_self_signed_cert.demo.cert_pem

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.demo.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

output "alb_https_url" {
  value = "https://${aws_lb.this.dns_name}"
}
