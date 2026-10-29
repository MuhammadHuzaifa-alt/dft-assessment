output "ec2_instance_id" {
  value = aws_instance.dft_hz_ec2.id
}

output "ec2_public_dns" {
  value = aws_instance.dft_hz_ec2.public_dns
}

output "s3_bucket_name" {
  value = aws_s3_bucket.dft_hz_fallback.bucket
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.dft_hz.domain_name
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.dft_hz.id
}