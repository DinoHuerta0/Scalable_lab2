#!/bin/bash
dnf install -y httpd
systemctl enable --now httpd

# IMDSv2 token
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
md() { curl -s -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/$1"; }

INSTANCE_ID=$(md instance-id)
AZ=$(md placement/availability-zone)
IP=$(md local-ipv4)

cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta http-equiv="refresh" content="3">
  <title>Load Balancer Test</title>
  <style>
    body { font-family: sans-serif; text-align: center; margin-top: 15vh; }
    .card { display: inline-block; padding: 2rem 3rem; border: 2px solid #232f3e; border-radius: 12px; }
  </style>
</head>
<body>
  <div class="card">
    <h1>Served by</h1>
    <p><strong>Instance ID:</strong> $INSTANCE_ID</p>
    <p><strong>Availability Zone:</strong> $AZ</p>
    <p><strong>Private IP:</strong> $IP</p>
  </div>
</body>
</html>
EOF

# Health check endpoint
echo "OK" > /var/www/html/health
