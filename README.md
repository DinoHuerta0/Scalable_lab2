# ALB + 2 EC2 Load Balancing Demo (Terraform)

A small AWS environment that proves an Application Load Balancer (ALB) distributes traffic across two EC2 instances. Each instance serves a simple web page showing its own **Instance ID, Availability Zone, and private IP**, so refreshing the ALB URL shows the page alternating between the two servers.

## Architecture

```
                 Internet
                     |
                     v
          +---------------------+
          |  Application Load   |   Listener: HTTP :80
          |  Balancer (ALB)     |   Algorithm: round robin
          +---------------------+
              |             |
     +--------+             +--------+
     v                               v
+-----------+                 +-----------+
|   EC2 #1  |                 |   EC2 #2  |
|   AZ "a"  |                 |   AZ "b"  |
|  Apache   |                 |  Apache   |
+-----------+                 +-----------+
```

- Two Amazon Linux 2023 instances, each in a different Availability Zone
- ALB with an HTTP listener on port 80 forwarding to one target group
- Target group health check on `/health`
- Security groups: the internet can reach the ALB on port 80, and the instances accept port 80 **only from the ALB**
- IMDSv2 enforced on the instances

## Files

| File | Purpose |
|------|---------|
| `main.tf` | All infrastructure: security groups, EC2 instances, ALB, target group, listener |
| `user_data.sh` | Boot script run once on each instance. Installs Apache, reads the instance metadata, and creates `index.html` and `/health` |
| `README.md` | This file |

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) 1.5 or later
- [AWS CLI](https://aws.amazon.com/cli/) configured with a profile named `academy`
- Permissions to create EC2 instances, security groups, and load balancers

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
terraform init
terraform apply
```

Type `yes` when prompted. When it finishes, get the ALB address:

```bash
terraform output alb_dns_name
```

Wait 1-2 minutes after the apply finishes. The instances need time to install Apache and pass their first health checks.

## Test

### 1. Open it in a browser

Go to `http://<alb_dns_name>`. The page refreshes every 3 seconds, and the **Instance ID** and **Availability Zone** should alternate between two values.

### 2. Test from the command line

Browsers reuse connections, so a request loop is more reliable.

**Windows CMD**

```cmd
for /f %u in ('terraform output -raw alb_dns_name') do @for /L %i in (1,1,10) do @curl.exe -s http://%u | findstr /C:"Instance ID"
```

In a `.bat` file, double the percent signs (`%%u`, `%%i`).

**Windows PowerShell**

```powershell
$url = terraform output -raw alb_dns_name
1..10 | ForEach-Object { curl.exe -s "http://$url" | Select-String "Instance ID" }
```

Use `curl.exe`, not `curl`, in PowerShell, because `curl` is an alias for `Invoke-WebRequest` there.

**Linux / macOS / Git Bash / WSL**

```bash
URL=$(terraform output -raw alb_dns_name)
for i in {1..10}; do curl -s http://$URL | grep "Instance ID"; done
```

You should see **two different instance IDs** across the 10 requests. That confirms the ALB is sending traffic to both EC2 instances.

### 3. Check target health

```bash
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups --names alb-demo-tg \
      --query 'TargetGroups[0].TargetGroupArn' --output text --profile academy) \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]' \
  --output table --profile academy
```

Both targets should show `healthy`. On Windows CMD, put the command on one line and remove the `\` line continuations.

### 4. Check the health endpoint

```bash
curl http://<alb_dns_name>/health
```

It should return `OK`.

### 5. Failover test (optional)

1. Stop one instance:
   ```bash
   aws ec2 stop-instances --instance-ids <instance-id> --profile academy
   ```
2. Wait about 30 seconds until the target shows `unhealthy` or `unused`.
3. Run the request loop again. Every response should now come from the remaining instance, with no errors.
4. Start the instance again. Once it turns healthy, the alternation resumes.

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
| Request times out | Your network may block outbound port 80, or the ALB security group was changed. |
| Only one instance appears | Use the request loop instead of manual browser refreshes. Make sure stickiness is off. |
| Targets stay `unhealthy` | Connect to an instance and check `/var/log/cloud-init-output.log` and `systemctl status httpd`. |
| `terraform output` prints nothing | Run it from the folder with `main.tf`, and confirm `terraform apply` completed. |
| `Profile could not be found` | The profile name is case-sensitive. Use `academy`, not `Academy`. |
| `ExpiredToken` errors | Refresh the credentials from the lab's "AWS Details" panel. |

## Clean up

Remove everything to avoid ongoing charges (the ALB bills by the hour):

```bash
terraform destroy
```

## Notes

- `user_data.sh` runs only on first boot. `user_data_replace_on_change = true` makes Terraform recreate the instances if you edit the script.
- The instances get public IPs only so they can reach the package repositories from the default VPC. In a custom VPC, place them in private subnets behind a NAT gateway.
- The demo uses plain HTTP. For HTTPS, add an ACM certificate and an HTTPS :443 listener on the ALB.
