output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.this.id
}

output "public_ip" {
  description = "Public IPv4 address of the EC2 instance."
  value       = aws_instance.this.public_ip
}

output "ssh_command" {
  description = "SSH command."
  value       = "ssh ec2-user@${aws_instance.this.public_ip}"
}

output "health_check_url" {
  description = "HTTP health check URL."
  value       = "http://${aws_instance.this.public_ip}:${var.http_port}/"
}

output "upload_url" {
  description = "HTTP upload endpoint for POST load tests."
  value       = "http://${aws_instance.this.public_ip}:${var.http_port}/upload"
}

output "download_url" {
  description = "HTTP download endpoint. Use ?mb=1, ?mb=10, etc."
  value       = "http://${aws_instance.this.public_ip}:${var.http_port}/download?mb=1"
}

output "cloudwatch_metric_hint" {
  description = "Main EC2 metrics to check."
  value       = "CloudWatch > EC2 > Per-Instance Metrics: NetworkIn, NetworkOut, NetworkPacketsIn, NetworkPacketsOut, CPUUtilization, CPUCreditBalance"
}