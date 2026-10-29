resource "aws_budgets_budget" "dft_hz_budget" {
  name         = "dft-hz-budget"
  budget_type  = "COST"
  limit_amount = "5"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}
resource "aws_vpc" "dft_hz_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "dft-hz-vpc"
  }
}

resource "aws_internet_gateway" "dft_hz_igw" {
  vpc_id = aws_vpc.dft_hz_vpc.id

  tags = {
    Name = "dft-hz-igw"
  }
}

resource "aws_route_table" "dft_hz_public" {
  vpc_id = aws_vpc.dft_hz_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.dft_hz_igw.id
  }

  tags = {
    Name = "dft-hz-public-rt"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "dft_hz_public_1" {
  vpc_id                  = aws_vpc.dft_hz_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "dft-hz-public-1"
  }
}

resource "aws_subnet" "dft_hz_public_2" {
  vpc_id                  = aws_vpc.dft_hz_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "dft-hz-public-2"
  }
}

resource "aws_route_table_association" "dft_hz_public_1" {
  subnet_id      = aws_subnet.dft_hz_public_1.id
  route_table_id = aws_route_table.dft_hz_public.id
}

resource "aws_route_table_association" "dft_hz_public_2" {
  subnet_id      = aws_subnet.dft_hz_public_2.id
  route_table_id = aws_route_table.dft_hz_public.id
}
resource "aws_iam_role" "dft_hz_ec2_role" {
  name = "dft-hz-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "dft-hz-ec2-role"
  }
}

resource "aws_iam_role_policy_attachment" "dft_hz_ssm" {
  role       = aws_iam_role.dft_hz_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "dft_hz_ec2_profile" {
  name = "dft-hz-ec2-profile"
  role = aws_iam_role.dft_hz_ec2_role.name

  tags = {
    Name = "dft-hz-ec2-profile"
  }
}

# CloudFront managed prefix list

data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

data "aws_caller_identity" "current" {}
# EC2 security group

resource "aws_security_group" "dft_hz_ec2" {
  name        = "dft-hz-ec2-sg"
  description = "Security group for dft-hz EC2"
  vpc_id      = aws_vpc.dft_hz_vpc.id

  ingress {
    description     = "HTTP from CloudFront only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "dft-hz-ec2-sg"
  }
}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# EC2 instance

resource "aws_instance" "dft_hz_ec2" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.dft_hz_public_1.id
  vpc_security_group_ids = [aws_security_group.dft_hz_ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.dft_hz_ec2_profile.name

  associate_public_ip_address = true
  user_data = templatefile("${path.module}/../scripts/ec2_user_data.sh", {
    app_code     = file("${path.module}/../app.py")
    requirements = file("${path.module}/../requirements.txt")
    git_sha      = var.git_sha
  })

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "dft-hz-ec2"
  }
}

resource "aws_s3_bucket" "dft_hz_fallback" {
  bucket = "dft-hz-fallback-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "dft-hz-fallback"
  }
}

resource "aws_s3_bucket_public_access_block" "dft_hz_fallback" {
  bucket = aws_s3_bucket.dft_hz_fallback.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "dft_hz_fallback_page" {
  bucket       = aws_s3_bucket.dft_hz_fallback.id
  key          = "index.html"
  source       = "${path.module}/../s3-fallback.html"
  content_type = "text/html"

  etag = filemd5("${path.module}/../s3-fallback.html")
}

resource "aws_s3_object" "dft_hz_fallback_health" {
  bucket       = aws_s3_bucket.dft_hz_fallback.id
  key          = "health"
  source       = "${path.module}/../s3-fallback.html"
  content_type = "text/html"

  etag = filemd5("${path.module}/../s3-fallback.html")
}

resource "aws_cloudfront_origin_access_control" "dft_hz_s3_oac" {
  name                              = "dft-hz-s3-oac"
  description                       = "OAC for private DFT fallback S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_iam_policy_document" "dft_hz_s3_policy" {
  statement {
    sid    = "AllowCloudFrontServicePrincipalReadOnly"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${aws_s3_bucket.dft_hz_fallback.arn}/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"

      values = [
        aws_cloudfront_distribution.dft_hz.arn
      ]
    }
  }
}

resource "aws_s3_bucket_policy" "dft_hz_fallback" {
  bucket = aws_s3_bucket.dft_hz_fallback.id
  policy = data.aws_iam_policy_document.dft_hz_s3_policy.json
}

resource "aws_cloudfront_distribution" "dft_hz" {
  enabled = true

  comment = "DFT Assessment - EC2 primary with S3 fallback"

  default_root_object = "index.html"

  origin {
    domain_name = aws_instance.dft_hz_ec2.public_dns
    origin_id   = "dft-hz-ec2"

    connection_attempts = 1
    connection_timeout  = 5

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]

      origin_read_timeout      = 5
      origin_keepalive_timeout = 5
    }
  }

  origin {
    domain_name = aws_s3_bucket.dft_hz_fallback.bucket_regional_domain_name
    origin_id   = "dft-hz-s3"

    origin_access_control_id = aws_cloudfront_origin_access_control.dft_hz_s3_oac.id
  }

  origin_group {
    origin_id = "dft-hz-origin-group"

    failover_criteria {
      status_codes = [500, 502, 503, 504]
    }

    member {
      origin_id = "dft-hz-ec2"
    }

    member {
      origin_id = "dft-hz-s3"
    }
  }

  default_cache_behavior {
    target_origin_id       = "dft-hz-origin-group"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = [
      "GET",
      "HEAD",
      "OPTIONS"
    ]

    cached_methods = [
      "GET",
      "HEAD"
    ]

    compress = true

    forwarded_values {
      query_string = true

      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  tags = {
    Name = "dft-hz-cloudfront"
  }
}

resource "aws_s3_bucket" "dft_hz_cloudtrail" {
  bucket = "dft-hz-cloudtrail-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "dft-hz-cloudtrail"
  }
}

resource "aws_s3_bucket_public_access_block" "dft_hz_cloudtrail" {
  bucket = aws_s3_bucket.dft_hz_cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "dft_hz_cloudtrail" {
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.dft_hz_cloudtrail.arn]
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions = ["s3:PutObject"]

    resources = [
      "${aws_s3_bucket.dft_hz_cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "dft_hz_cloudtrail" {
  bucket = aws_s3_bucket.dft_hz_cloudtrail.id
  policy = data.aws_iam_policy_document.dft_hz_cloudtrail.json
}

resource "aws_cloudtrail" "dft_hz" {
  name                          = "dft-hz-cloudtrail"
  s3_bucket_name                = aws_s3_bucket.dft_hz_cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_log_file_validation    = true

  tags = {
    Name = "dft-hz-cloudtrail"
  }

  depends_on = [
    aws_s3_bucket_policy.dft_hz_cloudtrail
  ]
}