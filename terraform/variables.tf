variable "aws_region" {
  description = "AWS region. Must be registered in the availability_zones map in vpc.tf"
  type        = string
  default     = "ap-northeast-1"

  validation {
    condition     = contains(["ap-northeast-1", "us-east-1", "us-west-2"], var.aws_region)
    error_message = "Region must be registered in the availability_zones map in vpc.tf."
  }
}

variable "environment" {
  description = "Environment tag (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "my-eks-cluster"
}

variable "kubernetes_version" {
  description = "Kubernetes version. Extended support versions incur an additional charge"
  type        = string
  default     = "1.34"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "ec2_key_pair_name" {
  description = "EC2 key pair for worker node SSH access. Empty string disables SSH"
  type        = string
  default     = ""
}

variable "node_group_min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 2

  validation {
    condition     = var.node_group_min_size >= 1
    error_message = "Minimum node count must be at least 1."
  }
}

variable "node_group_desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 2

  validation {
    condition     = var.node_group_desired_size >= var.node_group_min_size
    error_message = "Desired node count must be greater than or equal to the minimum."
  }
}

variable "node_group_max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 3

  validation {
    condition     = var.node_group_max_size >= var.node_group_desired_size
    error_message = "Maximum node count must be greater than or equal to the desired count."
  }
}

variable "instance_types" {
  description = "EC2 instance types for worker nodes"
  type        = list(string)
  default     = ["t3.small"]

  validation {
    condition     = length(var.instance_types) > 0
    error_message = "At least one instance type must be specified."
  }
}

variable "disk_size" {
  description = "Root volume size in GB. Applied through the launch template"
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size >= 20
    error_message = "Disk size must be at least 20GB."
  }
}

variable "capacity_type" {
  description = "Capacity type (ON_DEMAND or SPOT)"
  type        = string
  default     = "SPOT"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.capacity_type)
    error_message = "Capacity type must be ON_DEMAND or SPOT."
  }
}

variable "imds_hop_limit" {
  description = "IMDSv2 PUT response hop limit. Use 2 if pods need IMDS access, 1 if only the node does"
  type        = number
  default     = 2

  validation {
    condition     = var.imds_hop_limit >= 1 && var.imds_hop_limit <= 64
    error_message = "Hop limit must be between 1 and 64."
  }
}

variable "additional_tags" {
  description = "Additional tags applied to resources"
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 1

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Retention must be a value supported by CloudWatch Logs."
  }
}

variable "enabled_cluster_log_types" {
  description = "Control plane log types to enable. Enabling all increases CloudWatch ingestion cost"
  type        = list(string)
  default     = ["api", "audit"]

  validation {
    condition = length(setsubtract(var.enabled_cluster_log_types, [
      "api", "audit", "authenticator", "controllerManager", "scheduler"
    ])) == 0
    error_message = "Allowed values are api, audit, authenticator, controllerManager and scheduler."
  }
}

variable "single_nat_gateway" {
  description = "Create a single NAT gateway to reduce cost. Set false for per-AZ fault isolation"
  type        = bool
  default     = true
}

variable "endpoint_private_access" {
  description = "Enable the private API endpoint"
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Enable the public API endpoint"
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
