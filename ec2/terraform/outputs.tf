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
  value       = "ssh -i ${trimsuffix(var.ssh_public_key_path, ".pub")} ec2-user@${aws_instance.this.public_ip}"
}

output "health_check_url" {
  description = "HTTP health check URL, served through NGINX."
  value       = "http://${aws_instance.this.public_ip}:${var.lb_port}/"
}

output "upload_url" {
  description = "HTTP upload endpoint for POST load tests."
  value       = "http://${aws_instance.this.public_ip}:${var.lb_port}/upload"
}

output "download_url" {
  description = "HTTP download endpoint. Use ?mb=1, ?mb=10, etc."
  value       = "http://${aws_instance.this.public_ip}:${var.lb_port}/download?mb=1"
}

output "ansible_command" {
  description = "Command to configure the instance with Ansible."
  value       = "EC2_HOST=${aws_instance.this.public_ip} ansible-playbook -i ansible/inventory_ec2.yaml ansible/playbook_ec2.yaml"
}

output "cloudwatch_metric_hint" {
  description = "Main EC2 metrics to check."
  value       = "CloudWatch > EC2 > Per-Instance Metrics: NetworkIn, NetworkOut, NetworkPacketsIn, NetworkPacketsOut, CPUUtilization, CPUCreditBalance"
}