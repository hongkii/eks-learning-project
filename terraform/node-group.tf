# =============================================================================
# EKS 노드 그룹 및 Launch Template 설정
# =============================================================================
# 이 파일은 EKS 워커 노드와 관련 설정을 정의합니다.
# - EKS 노드 그룹 생성 (Amazon Linux 2023)
# - 오토 스케일링 설정
# - Launch Template (고급 설정)
# - IMDSv2 보안 강화
# - SSH 접근 설정 (동적)
# =============================================================================

# EKS 1.33 지원 워커 노드 그룹 - 베스트 프랙티스: 프라이빗 서브넷 배치
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name # eks.tf 클러스터 참조
  node_group_name = "${var.cluster_name}-node-group"
  node_role_arn   = aws_iam_role.eks_node_group.arn # iam.tf 노드 그룹 IAM 역할

  subnet_ids = aws_subnet.private[*].id # vpc.tf 프라이빗 서브넷 배치

  # AL2023 AMI - K8s 1.33에서 AL2 지원 종료로 필수 마이그레이션
  ami_type = "AL2023_x86_64_STANDARD"

  instance_types = var.instance_types # variables.tf 인스턴스 타입
  disk_size      = var.disk_size      # variables.tf 디스크 크기

  scaling_config {
    desired_size = var.node_group_desired_size
    max_size     = var.node_group_max_size
    min_size     = var.node_group_min_size
  }

  update_config {
    max_unavailable_percentage = 25 # Rolling update 전략
  }

  capacity_type = var.capacity_type

  dynamic "remote_access" {
    for_each = var.ec2_key_pair_name != "" ? [1] : []
    content {
      ec2_ssh_key               = var.ec2_key_pair_name
      source_security_group_ids = [aws_security_group.eks_nodes.id]
    }
  }

  labels = {
    role        = "worker"
    environment = var.environment
  }

  # IAM 역할 정책이 모두 연결된 후 노드 그룹 생성
  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,        # iam.tf 노드 역할 정책
    aws_iam_role_policy_attachment.eks_cni_policy,                # iam.tf CNI 정책 (ENI 관리)
    aws_iam_role_policy_attachment.eks_container_registry_policy, # iam.tf ECR 접근 정책
  ]

  tags = {
    Name                                        = "${var.cluster_name}-node-group"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size] # ASG가 제어
  }
}

# 선택적: 고급 노드 설정 (IMDSv2, 사용자 데이터 등)
resource "aws_launch_template" "eks_nodes" {
  name = "${var.cluster_name}-node-template"

  vpc_security_group_ids = [aws_security_group.eks_nodes.id] # security-groups.tf 노드 SG

  # EKS 1.33 베스트 프랙티스: IMDSv2 강제 사용
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv1 차단, 보안 강화
    http_put_response_hop_limit = 2
  }

  monitoring {
    enabled = true # CloudWatch 메트릭 수집
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.cluster_name}-worker-node"
    }
  }

  tags = {
    Name = "${var.cluster_name}-node-template"
  }
}