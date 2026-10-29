# Build Log

## DFT DevOps Technical Assessment

This document records significant implementation problems encountered during the deployment and the fixes applied.

---

## 1. CloudFront Terraform Arguments Were Unsupported

### Problem

The initial CloudFront Terraform configuration used unsupported arguments for the AWS provider version being used.

Terraform rejected the CloudFront configuration during validation/plan.

### Fix

The unsupported origin connection arguments were removed and the supported CloudFront origin configuration was used.

The final configuration uses:

- `connection_attempts`
- `connection_timeout`
- `origin_read_timeout`
- `origin_keepalive_timeout`

### Result

Terraform validation and deployment completed successfully.

---

## 2. SSM Session Manager Was Initially Not Working

### Problem

The EC2 instance was configured for AWS Systems Manager Session Manager, but the local Windows environment initially had an issue starting an SSM session.

### Investigation

The EC2 instance had:

- An IAM role
- `AmazonSSMManagedInstanceCore`
- Systems Manager configuration

The issue was related to the local SSM Session Manager/plugin setup rather than the EC2 application.

### Fix

The local SSM tooling was corrected and the following command successfully established a session:

```bash
aws ssm start-session --target <instance-id> --region eu-north-1
```

### Result

The EC2 instance could be administered without opening SSH port 22.

---

## 3. Git SHA Initially Returned `unknown`

### Problem

The `/health` endpoint initially returned:

```json
"git_sha": "unknown"
```

The application attempted to obtain the Git SHA by running Git commands on the EC2 instance.

### Cause

The application source was copied to EC2 through Terraform/user data without the local `.git` repository.

Therefore the EC2 instance did not have the Git repository metadata required by `git rev-parse`.

### Fix

The deployment was changed to pass the Git commit SHA into the EC2 environment.

The application reads:

```text
DFT_GIT_SHA
```

and the systemd service loads:

```text
/etc/dft/dft-app.env
```

### Result

The deployed application now reports:

```json
"git_sha": "392e628"
```

---

## 4. Terraform `user_data` Change Did Not Update the Existing EC2 Application

### Problem

After updating the Terraform configuration to create `/etc/dft/dft-app.env`, the existing EC2 instance still did not contain the file.

The service also did not contain:

```ini
EnvironmentFile=/etc/dft/dft-app.env
```

### Cause

EC2 user data is primarily a bootstrap mechanism executed during instance initialization. Updating the Terraform configuration did not cause the existing instance's bootstrap process to run again.

### Fix

The EC2 instance was explicitly replaced using:

```bash
terraform apply -replace="aws_instance.dft_hz_ec2"
```

### Result

The new EC2 instance executed the updated bootstrap script.

The resulting service contained:

```ini
EnvironmentFile=/etc/dft/dft-app.env
```

and:

```text
DFT_GIT_SHA=392e628
```

---

## 5. Maintenance Mode Needed to Restore Without Restarting the Application

### Problem

The assessment required the application to return HTTP 503 while a maintenance file exists and to recover when the file is removed without restarting the application.

### Fix

The Flask application checks for:

```text
/etc/dft/maintenance
```

on every `/health` request.

When the file exists, the endpoint returns HTTP 503.

When the file is removed, normal operation resumes.

### Test

Enable maintenance:

```bash
sudo touch /etc/dft/maintenance
```

Disable maintenance:

```bash
sudo rm /etc/dft/maintenance
```

### Result

The application successfully changed between HTTP 503 and HTTP 200 without restarting the Flask service.

---

## 6. CloudFront Failover Was Tested

### Problem

The assessment required CloudFront to automatically use the S3 fallback when the EC2 origin becomes unavailable.

### Fix

CloudFront was configured with an origin group containing:

1. EC2 as the primary origin
2. Private S3 as the secondary origin

The failover status codes include:

```text
500
502
503
504
```

### Test

EC2 maintenance mode was enabled so the application returned HTTP 503.

CloudFront then served:

```text
served_by: s3-fallback
```

### Result

The failover mechanism was successfully observed and recorded in:

```text
evidence/failover-run.log
```

---

## 7. CloudFront Origin Configuration Required Adjustment

### Problem

During Terraform deployment, the CloudFront origin configuration required adjustment before the final configuration could be applied successfully.

### Fix

The CloudFront configuration was corrected to use supported origin settings and the distribution was successfully deployed.

### Result

The final CloudFront distribution successfully routes healthy requests to EC2 and failed requests to the S3 fallback.

---

## Final Verification

The final CloudFront `/health` response successfully returned:

```text
HTTP/1.1 200 OK
X-DFT-Ref: DFT-HZ-B7KF-S4VW
X-Cache: Miss from cloudfront
```

with:

```json
{
  "served_by": "ec2",
  "git_sha": "392e628",
  "region": "eu-north-1"
}
```

The final EC2 instance was deployed through Terraform and configured automatically through EC2 user data.