# DFT DevOps Technical Assessment

## Overview

This project deploys a Python Flask health-check application on AWS with automatic failover from an EC2 primary origin to a private S3 fallback through Amazon CloudFront.

### AWS Region

`eu-north-1` — Stockholm

### Candidate Reference

`DFT-HZ-B7KF-S4VW`

## Architecture

```text
                         Internet
                            |
                            v
                    +----------------+
                    |  Amazon        |
                    |  CloudFront    |
                    +-------+--------+
                            |
                     Origin Group
                     /           \
                    /             \
                   v               v
          +---------------+   +---------------+
          | EC2 Primary   |   | Private S3    |
          |               |   | Fallback      |
          | Nginx :80     |   |               |
          |      |        |   | served_by:    |
          | Flask :8000   |   | s3-fallback   |
          +---------------+   +---------------+
                   |
                   v
             /health endpoint

CloudFront uses the EC2 origin as the primary origin and
the private S3 origin as the failover origin for HTTP 500,
502, 503 and 504 responses.
```

## Components

- Amazon VPC
- Two public subnets in different Availability Zones
- Internet Gateway
- One Amazon Linux 2023 EC2 instance
- Nginx reverse proxy
- Flask application
- AWS Systems Manager Session Manager
- Private Amazon S3 fallback bucket
- CloudFront Origin Access Control (OAC)
- CloudFront origin group
- AWS Budget alert
- Terraform

## Application

The `/health` endpoint returns:

- `status`
- `served_by`
- `instance_id`
- `availability_zone`
- `region`
- `candidate_ref`
- `git_sha`
- `time`

The instance ID and Availability Zone are obtained from the EC2 Instance Metadata Service.

IMDSv2 is required.

Every response includes:

```text
X-DFT-Ref: DFT-HZ-B7KF-S4VW
```

## Maintenance Mode

The application checks for:

```text
/etc/dft/maintenance
```

When the file exists, `/health` returns HTTP `503`.

Removing the file restores the application without restarting the Flask service.

Example:

```bash
sudo touch /etc/dft/maintenance
```

Disable maintenance:

```bash
sudo rm /etc/dft/maintenance
```

## EC2 Configuration

The Flask application runs as the non-root `dftapp` system user through systemd.

The service uses:

```text
/opt/dft-app/venv/bin/python /opt/dft-app/app.py
```

Nginx listens on port 80 and proxies requests to Flask on port 8000.

SSH port 22 is not opened in the EC2 security group.

Session Manager is used for administrative access.

## Security

The EC2 security group permits HTTP traffic only from the AWS CloudFront origin-facing managed prefix list.

The S3 bucket is private.

Public S3 access is blocked and CloudFront accesses the bucket using Origin Access Control and SigV4.

The EC2 root volume is encrypted.

The EC2 instance requires IMDSv2.

Terraform state files, Terraform variables containing personal values, credentials and secrets are excluded from Git.

## Deployment

Prerequisites:

- AWS CLI
- Terraform >= 1.6
- AWS credentials configured
- Git

Configure AWS credentials:

```bash
aws configure
```

Verify:

```bash
aws sts get-caller-identity
```

Go to the Terraform directory:

```bash
cd terraform
```

Create `terraform.tfvars` with the required local variables.

Format and validate:

```bash
terraform fmt
terraform validate
```

Review the deployment:

```bash
terraform plan
```

Deploy:

```bash
terraform apply
```

Get outputs:

```bash
terraform output
```

## Testing

Test the CloudFront health endpoint:

```bash
curl.exe -i https://<cloudfront-domain>/health
```

A healthy response should contain:

```text
HTTP/1.1 200 OK
X-DFT-Ref: DFT-HZ-B7KF-S4VW
```

and:

```json
"served_by":"ec2"
```

## Failover Test

The failover monitoring script checks the CloudFront `/health` endpoint every two seconds.

Run:

```bash
python scripts/failover_check.py
```

The test log is stored at:

```text
evidence/failover-run.log
```

To trigger application maintenance:

```bash
sudo touch /etc/dft/maintenance
```

CloudFront should then fail over to the S3 fallback.

The fallback page contains:

```text
served_by: s3-fallback
```

Remove maintenance:

```bash
sudo rm /etc/dft/maintenance
```

The primary EC2 origin should become available again.

## Destroy

After the assessment and video call are complete:

```bash
cd terraform
terraform destroy
```

Review the resources carefully before confirming destruction.

## Known Weaknesses

1. The deployment uses a single EC2 primary instance, so the EC2 application itself is not highly available.
2. The S3 fallback provides a static emergency page rather than the full application.
3. The EC2 instance is in a public subnet, although application access is restricted to CloudFront and administrative access uses SSM.
4. CloudFront is the public entry point and therefore represents an important dependency.
5. The current deployment does not provide application-level horizontal scaling.

## Evidence

Deployment and testing evidence is stored under:

```text
evidence/
```

including the failover test log and assessment screenshots/exports.

## Terraform Resources

Terraform manages the AWS infrastructure so the environment is reproducible and can be destroyed cleanly after the assessment.