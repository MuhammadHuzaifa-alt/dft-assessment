#!/bin/bash

set -e

dnf update -y
dnf install -y python3 python3-pip nginx git

# Create application user
useradd --system --create-home --shell /sbin/nologin dftapp || true

# Create application directories
mkdir -p /opt/dft-app
mkdir -p /etc/dft

# Store the assessment reference in a variable
heron_tag="DFT-HZ-B7KF-S4VW"

# Copy application files from Terraform template
cat > /opt/dft-app/app.py <<'PYTHON'
${app_code}
PYTHON

cat > /opt/dft-app/requirements.txt <<'REQUIREMENTS'
${requirements}
REQUIREMENTS

# Create Python virtual environment
python3 -m venv /opt/dft-app/venv

# Install Python dependencies
/opt/dft-app/venv/bin/pip install --upgrade pip
/opt/dft-app/venv/bin/pip install -r /opt/dft-app/requirements.txt

# Set ownership
chown -R dftapp:dftapp /opt/dft-app
chown -R dftapp:dftapp /etc/dft

# Create systemd service
cat > /etc/systemd/system/dft-app.service <<'SERVICE'
[Unit]
Description=DFT Assessment Flask Application
After=network.target

[Service]
Type=simple
User=dftapp
Group=dftapp
WorkingDirectory=/opt/dft-app
ExecStart=/opt/dft-app/venv/bin/python /opt/dft-app/app.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SERVICE

# Reload systemd and start Flask application
systemctl daemon-reload
systemctl enable dft-app
systemctl start dft-app

# Configure Nginx
cat > /etc/nginx/conf.d/dft-app.conf <<'NGINX'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:8000;

        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX

# Test Nginx configuration
nginx -t

# Enable and start Nginx
systemctl enable nginx
systemctl restart nginx

echo "DFT EC2 setup completed successfully."