
variable "aws_region" {
  description = "EKS 클러스터를 생성할 AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "environment" {
  description = "환경 구분 태그 (dev, staging, prod 등)"
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "EKS 클러스터 이름 (고유해야 함)"
  type        = string
  default     = "my-eks-cluster"
}

variable "kubernetes_version" {
  description = "EKS 클러스터에서 사용할 쿠버네티스 버전"
  type        = string
  default     = "1.33"
}

variable "vpc_cidr" {
  description = "VPC에서 사용할 CIDR 블록"
  type        = string
  default     = "10.0.0.0/16"
}

variable "ec2_key_pair_name" {
  description = "워커 노드 SSH 접근을 위한 EC2 키 페어 이름"
  type        = string
  default     = ""
}

variable "node_group_min_size" {
  description = "오토 스케일링 그룹의 최소 노드 수"
  type        = number
  default     = 2

  validation {
    condition     = var.node_group_min_size >= 2
    error_message = "노드 그룹 최소 크기는 2 이상이어야 합니다."
  }
}

variable "node_group_desired_size" {
  description = "오토 스케일링 그룹의 희망 노드 수"
  type        = number
  default     = 2

  validation {
    condition     = var.node_group_desired_size >= var.node_group_min_size
    error_message = "희망 노드 수는 최소 노드 수보다 크거나 같아야 합니다."
  }
}

variable "node_group_max_size" {
  description = "오토 스케일링 그룹의 최대 노드 수"
  type        = number
  default     = 3

  validation {
    condition     = var.node_group_max_size >= var.node_group_desired_size
    error_message = "최대 노드 수는 희망 노드 수보다 크거나 같아야 합니다."
  }
}

variable "instance_types" {
  description = "워커 노드에서 사용할 EC2 인스턴스 타입 목록"
  type        = list(string)
  default     = ["t3.small"]

  validation {
    condition     = length(var.instance_types) > 0
    error_message = "최소 하나의 인스턴스 타입이 지정되어야 합니다."
  }
}

variable "disk_size" {
  description = "워커 노드의 EBS 볼륨 크기 (GB)"
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size >= 20
    error_message = "디스크 크기는 최소 20GB 이상이어야 합니다."
  }
}

variable "capacity_type" {
  description = "인스턴스 용량 타입 (ON_DEMAND 또는 SPOT)"
  type        = string
  default     = "SPOT"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.capacity_type)
    error_message = "용량 타입은 ON_DEMAND 또는 SPOT이어야 합니다."
  }
}

variable "additional_tags" {
  description = "리소스에 추가할 사용자 정의 태그"
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "CloudWatch 로그 보존 기간 (일)"
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "로그 보존 기간은 CloudWatch에서 지원하는 값이어야 합니다."
  }
}

variable "endpoint_private_access" {
  description = "EKS 클러스터의 프라이빗 API 엔드포인트 활성화 여부"
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "EKS 클러스터의 퍼블릭 API 엔드포인트 활성화 여부"
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "퍼블릭 API 엔드포인트 접근을 허용할 CIDR 블록 목록"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

