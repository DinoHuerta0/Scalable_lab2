# Lab 2: AWS Infrastructure with Terraform

This repository contains the Terraform configuration for provisioning an AWS infrastructure with two EC2 instances exposed via an Application Load Balancer (ALB) with path-based routing, fronted by an HTTP API Gateway through a VPC Link.

## Architecture Overview

```
Internet → API Gateway (Public) → VPC Link → ALB (Internal) → EC2 Instance (App1 or App2)
```

The configuration provisions the following AWS resources:

| Resource | Details |
|---|---|
| **VPC** | `10.0.0.0/16` with 2 public subnets across `us-east-1a` and `us-east-1b` |
| **Internet Gateway** | Allows outbound internet access from EC2 instances |
| **Security Groups** | `alb-sg` (allows HTTP 80 from anywhere), `ec2-sg` (allows HTTP 80 from ALB only) |
| **EC2 Instances** | Two `t2.micro` Amazon Linux 2 instances running Apache HTTP server |
| **ALB** | Internal Application Load Balancer with path-based routing rules |
| **Target Groups** | `app1-tg` and `app2-tg`, one per EC2 instance |
| **API Gateway (HTTP)** | Public-facing HTTP API that receives all external traffic |
| **VPC Link** | Connects the API Gateway privately to the internal ALB |

### Path-Based Routing

| Request Path | Target |
|---|---|
| `/app1*` | EC2 Instance 1 — responds with `<h1>App 1</h1>` plus its instance metadata (instance ID, AZ, private IP, instance type) |
| `/app2*` | EC2 Instance 2 — responds with `<h1>App 2</h1>` plus its instance metadata (instance ID, AZ, private IP, instance type) |
| anything else | ALB returns `404: Not Found` |

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) installed.
- [AWS CLI](https://aws.amazon.com/cli/) configured with a profile named `academy`.

## Usage

1. **Initialize Terraform** — downloads provider plugins:
   ```bash
   terraform init
   ```

2. **Review the execution plan:**
   ```bash
   terraform plan
   ```

3. **Apply the configuration** — provisions all AWS resources:
   ```bash
   terraform apply
   ```
   When complete, Terraform will print the API Gateway URL:
   ```
   Outputs:
   api_gateway_url = "https://<api-id>.execute-api.us-east-1.amazonaws.com/"
   ```

4. **Destroy resources** when done to avoid unnecessary costs:
   ```bash
   terraform destroy
   ```

## Testing Path-Based Routing

After `terraform apply` completes, use the printed `api_gateway_url` to test the routing.

> **Note for PowerShell users:** `curl` in PowerShell is an alias for `Invoke-WebRequest`. Use `curl.exe` to call the real curl binary, or use the `Invoke-WebRequest` cmdlet.

### Using `curl.exe` (PowerShell / Windows)
```powershell
# Should return: <h1>App 1</h1> plus instance metadata (instance ID, AZ, private IP, instance type)
curl.exe https://<api-id>.execute-api.us-east-1.amazonaws.com/app1/index.html

# Should return: <h1>App 2</h1> plus instance metadata (instance ID, AZ, private IP, instance type)
curl.exe https://<api-id>.execute-api.us-east-1.amazonaws.com/app2/index.html
```

Example output for `/app1`:
```html
<h1>App 1</h1>
<ul>
  <li><strong>Instance ID:</strong> i-0abc123def456789</li>
  <li><strong>Availability Zone:</strong> us-east-1a</li>
  <li><strong>Private IP:</strong> 10.0.1.XX</li>
  <li><strong>Instance Type:</strong> t2.micro</li>
</ul>
```

### Using `Invoke-WebRequest` (PowerShell)
```powershell
Invoke-WebRequest -Uri "https://<api-id>.execute-api.us-east-1.amazonaws.com/app1/index.html"
Invoke-WebRequest -Uri "https://<api-id>.execute-api.us-east-1.amazonaws.com/app2/index.html"
```

### Using `curl` (Linux / macOS / Git Bash)
```bash
curl https://<api-id>.execute-api.us-east-1.amazonaws.com/app1/index.html
curl https://<api-id>.execute-api.us-east-1.amazonaws.com/app2/index.html
```

> **Tip:** It may take ~1 minute after `apply` for the EC2 instances to finish installing Apache. If you get a `502 Bad Gateway`, wait a moment and try again.
