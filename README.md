# ALB + 2 EC2 Load Balancing Demo (Terraform)

A small AWS environment that proves an Application Load Balancer (ALB) distributes traffic across two EC2 instances. Each instance serves a simple web page showing its own **Instance ID, Availability Zone, and private IP**, so refreshing the ALB URL shows the page alternating between the two servers.

The ALB serves the site over **HTTPS** (self-signed certificate for the demo) and redirects plain HTTP to HTTPS.

## Architecture

```
                 Internet
                     |
                     v
          +---------------------+
          |  Application Load   |   HTTP  :80  -> 301 redirect to HTTPS
          |  Balancer (ALB)     |   HTTPS :443 -> forward (TLS ends here)
          +---------------------+   Algorithm: round robin
              |             |
     +--------+             +--------+     plain HTTP :80
     v                               v
+-----------+                 +-----------+
|   EC2 #1  |                 |   EC2 #2  |
|   AZ "a"  |                 |   AZ "b"  |
|  Apache   |                 |  Apache   |
+-----------+                 +-----------+
```

- Two Amazon Linux 2023 instances, each in a different Availability Zone
- ALB with an HTTPS listener on 443 (forwards to one target group) and an HTTP listener on 80 that redirects to HTTPS
- TLS is terminated at the ALB. Traffic from the ALB to the instances is plain HTTP on port 80
- Target group health check on `/health`
- Security groups: the internet can reach the ALB on ports 80 and 443, and the instances accept port 80 **only from the ALB**
- IMDSv2 enforced on the instances

## Files

| File | Purpose |
|------|---------|
| `main.tf` | Core infrastructure: security groups, EC2 instances, ALB, target group, HTTP redirect listener |
| `https.tf` | Self-signed certificate, import into ACM, and the HTTPS listener on 443 |
| `user_data.sh` | Boot script run once on each instance. Installs Apache, reads the instance metadata, and creates `index.html` and `/health` |
| `test.bat` | Windows script that tests the load balancing over HTTPS and checks the HTTP redirect |
| `README.md` | This file |

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) 1.5 or later
- [AWS CLI](https://aws.amazon.com/cli/) configured with a profile named `academy`
- Permissions to create EC2 instances, security groups, load balancers, and to import certificates into ACM

Check that your credentials work:

```bash
aws sts get-caller-identity --profile academy
```

> **AWS Academy Learner Lab:** credentials expire when the lab session ends. If Terraform fails with an `ExpiredToken` or authentication error, copy the fresh credentials from the lab's "AWS Details" panel into `~/.aws/credentials` under the `[academy]` profile. Profile names are case-sensitive.

## Configuration

Defaults are defined as variables in `main.tf`:

| Variable | Default | Description |
|----------|---------|-------------|
| `profile` | `academy` | AWS CLI profile used by Terraform |
| `region` | `us-east-1` | AWS region |
| `instance_type` | `t3.micro` | EC2 instance size |
| `instance_count` | `2` | Number of instances (one per AZ, up to the AZs available in the region) |

Override any of them on the command line:

```bash
terraform apply -var region=us-west-2 -var profile=other
```

## Deploy

Run these from the folder that contains `main.tf`:

```bash
terraform init -upgrade
terraform apply
```

Type `yes` when prompted. `init -upgrade` downloads both the `aws` and `tls` providers. When it finishes, get the ALB address:

```bash
terraform output alb_dns_name
```

Wait 1-2 minutes after the apply finishes. The instances need time to install Apache and pass their first health checks.

## Test

### 1. Open it in a browser

Go to `https://<alb_dns_name>`. Because the certificate is self-signed, the browser shows a "connection is not private" warning. Choose "Advanced" and continue. The page refreshes every 3 seconds, and the **Instance ID** and **Availability Zone** should alternate between two values.

### 2. Test from the command line

Browsers reuse connections, so a request loop is more reliable. The `-k` flag is required because the certificate is self-signed.

**Windows CMD or PowerShell: run the script**

```cmd
test.bat
```

In PowerShell, use `.\test.bat`. The script sends 10 HTTPS requests and then checks the HTTP redirect.

**Windows CMD (one-liner)**

```cmd
for /f %u in ('terraform output -raw alb_dns_name') do @for /L %i in (1,1,10) do @curl.exe -k -s https://%u | findstr /C:"Instance ID"
```

**Windows PowerShell**

```powershell
$url = terraform output -raw alb_dns_name
1..10 | ForEach-Object { curl.exe -k -s "https://$url" | Select-String "Instance ID" }
```

Use `curl.exe`, not `curl`, in PowerShell, because `curl` is an alias for `Invoke-WebRequest` there.

**Linux / macOS / Git Bash / WSL**

```bash
URL=$(terraform output -raw alb_dns_name)
for i in {1..10}; do curl -k -s https://$URL | grep "Instance ID"; done
```

You should see **two different instance IDs** across the 10 requests. That confirms the ALB is sending traffic to both EC2 instances.

### 3. Check the HTTP to HTTPS redirect

```bash
curl -s -I http://<alb_dns_name>
```

Expected output:

```
HTTP/1.1 301 Moved Permanently
Location: https://<alb_dns_name>:443/
```

`301` means "moved permanently". The ALB answers plain HTTP requests with a redirect to the HTTPS address. Port `:443` is the default for HTTPS, so `https://host/` and `https://host:443/` are the same address. To follow the redirect and get the page, add `-L -k`:

```bash
curl -k -L http://<alb_dns_name>
```

### 4. Check target health

```bash
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups --names alb-demo-tg \
      --query 'TargetGroups[0].TargetGroupArn' --output text --profile academy) \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]' \
  --output table --profile academy
```

Both targets should show `healthy`. On Windows CMD, put the command on one line and remove the `\` line continuations.

### 5. Check the health endpoint

The health check is served by the instances over HTTP, so it is only reachable through the ALB's HTTPS listener:

```bash
curl -k https://<alb_dns_name>/health
```

It should return `OK`.

### 6. Failover test (optional)

1. Stop one instance:
   ```bash
   aws ec2 stop-instances --instance-ids <instance-id> --profile academy
   ```
2. Wait about 30 seconds until the target shows `unhealthy` or `unused`.
3. Run the request loop again. Every response should now come from the remaining instance, with no errors.
4. Start the instance again. Once it turns healthy, the alternation resumes.

## HTTPS and certificates

ACM cannot issue a public certificate for the `*.elb.amazonaws.com` name, so `https.tf` generates a **self-signed certificate** and imports it into ACM. It encrypts the traffic, but browsers do not trust it, which is why you see a warning and need `-k` with curl. The certificate is valid for 30 days.

### Using a real domain (no browser warning)

If you own a domain (for example in Route 53), replace the three certificate resources in `https.tf` (`tls_private_key`, `tls_self_signed_cert`, `aws_acm_certificate`) with an ACM certificate that uses DNS validation, and point the HTTPS listener's `certificate_arn` at `aws_acm_certificate_validation.demo.certificate_arn`:

```hcl
variable "domain_name" { type = string } # e.g. demo.example.com

data "aws_route53_zone" "this" {
  name = "example.com"
}

resource "aws_acm_certificate" "demo" {
  domain_name       = var.domain_name
  validation_method = "DNS"
}

resource "aws_route53_record" "validation" {
  for_each = {
    for o in aws_acm_certificate.demo.domain_validation_options : o.domain_name => o
  }
  zone_id = data.aws_route53_zone.this.zone_id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  records = [each.value.resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "demo" {
  certificate_arn         = aws_acm_certificate.demo.arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}

resource "aws_route53_record" "alb" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}
```

Then browse to your own domain over HTTPS. Route 53 and domain features may be restricted in AWS Academy Learner Labs.

## Changing the load balancing algorithm

In `main.tf`, edit `load_balancing_algorithm_type` in the target group:

- `round_robin` (default): requests alternate between targets
- `least_outstanding_requests`: better when request times vary a lot
- `weighted_random`: random distribution with automatic anomaly mitigation

Stickiness is disabled so that the alternation stays visible.

## Troubleshooting

| Symptom | Likely cause and fix |
|---------|----------------------|
| `503 Service Unavailable` | No healthy targets yet. Wait 1-2 minutes, then check target health. |
| Browser warns the connection is not private | Expected with the self-signed certificate. Continue past the warning, or use a real domain and ACM certificate. |
| curl fails with a certificate error | Add `-k` to accept the self-signed certificate. |
| `curl` in PowerShell rejects `-k` or `-s` | Use `curl.exe` instead of `curl`. |
| Request times out | Your network may block outbound ports 80/443, or the ALB security group was changed. |
| Only one instance appears | Use the request loop instead of manual browser refreshes. Make sure stickiness is off. |
| Targets stay `unhealthy` | Connect to an instance and check `/var/log/cloud-init-output.log` and `systemctl status httpd`. |
| `terraform output` prints nothing | Run it from the folder with `main.tf`, and confirm `terraform apply` completed. |
| `Profile could not be found` | The profile name is case-sensitive. Use `academy`, not `Academy`. |
| `ExpiredToken` errors | Refresh the credentials from the lab's "AWS Details" panel. |
| `Inconsistent dependency lock file` or missing `tls` provider | Run `terraform init -upgrade`. |
| Access denied importing the ACM certificate | The account may restrict ACM. Check the exact error message. |

## Clean up

Remove everything to avoid ongoing charges (the ALB bills by the hour):

```bash
terraform destroy
```

## Notes

- `user_data.sh` runs only on first boot. `user_data_replace_on_change = true` makes Terraform recreate the instances if you edit the script.
- The instances get public IPs only so they can reach the package repositories from the default VPC. In a custom VPC, place them in private subnets behind a NAT gateway.
- TLS ends at the ALB. If you need end-to-end encryption, configure HTTPS on the instances and set the target group protocol to HTTPS.
