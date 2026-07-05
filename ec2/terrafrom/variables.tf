variable "aws_region" {
  description = "AWS region to deploy into. us-east-1 is usually cheap; ap-northeast-1 gives Japan-like latency."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix for resource names."
  type        = string
  default     = "http-traffic-lab"
}

variable "instance_type" {
  description = "Cheapest default is t4g.nano. This requires an ARM64 AMI."
  type        = string
  default     = "t4g.nano"
}

variable "my_ip_cidr" {
  description = "Your public IP in CIDR format, for example 203.0.113.10/32. This is used for SSH and HTTP access."
  type        = string

  validation {
    condition     = can(cidrhost(var.my_ip_cidr, 0))
    error_message = "my_ip_cidr must be a valid CIDR block, for example 203.0.113.10/32."
  }
}

variable "ssh_public_key_path" {
  description = "Path to your SSH public key. Example: ~/.ssh/id_ed25519.pub"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "http_port" {
  description = "HTTP test server port."
  type        = number
  default     = 8000
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GB. Keep small for cheapest setup."
  type        = number
  default     = 8
}

variable "enable_detailed_monitoring" {
  description = "Set true for 1-minute CloudWatch EC2 metrics. False is cheaper and uses basic monitoring."
  type        = bool
  default     = false
}