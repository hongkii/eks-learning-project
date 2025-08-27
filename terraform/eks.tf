# =============================================================================
# EKS 클러스터 및 애드온 설정
# =============================================================================
# 이 파일은 EKS 클러스터와 필수 애드온을 정의합니다.
# - EKS 클러스터 생성 (Kubernetes 1.33)
# - 컨트롤 플레인 로깅 설정
# - KMS 암호화 설정
# - EKS 애드온 (CoreDNS, VPC-CNI, kube-proxy, EBS-CSI)
# - CloudWatch 로그 그룹
# =============================================================================

# EKS 1.33 쿠버네티스 컨트롤 플레인 (variables.tf:22에서 버전 지정)
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name             # variables.tf cluster_name 참조
  role_arn = aws_iam_role.eks_cluster.arn # iam.tf에서 생성한 IAM 역할
  version  = var.kubernetes_version       # variables.tf:22 "1.33" 버전

  # 베스트 프랙티스: 컨트롤 플레인 ENI를 프라이빗 서브넷에 배치
  vpc_config {
    subnet_ids = aws_subnet.private[*].id # vpc.tf 프라이빗 서브넷 참조

    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.public_access_cidrs

    security_group_ids = [aws_security_group.eks_cluster.id] # security-groups.tf 참조
  }

  # 전체 컨트롤 플레인 로그 활성화
  enabled_cluster_log_types = [
    "api", "audit", "authenticator", "controllerManager", "scheduler"
  ]

  # etcd 암호화 설정
  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy, # iam.tf IAM 역할 정책
    aws_cloudwatch_log_group.eks_cluster,              # 로그 그룹 먼저 생성
  ]

  tags = {
    Name = var.cluster_name
  }
}

resource "aws_kms_key" "eks" {
  description             = "EKS Secret Encryption Key for ${var.cluster_name}"
  deletion_window_in_days = 7 # 최소 삭제 대기 기간

  tags = {
    Name = "${var.cluster_name}-eks-encryption-key"
  }
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.cluster_name}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.cluster_name}-cluster-logs"
  }
}

# EBS CSI Driver v2 addon - 영구 볼륨 관리 (K8s 1.33+ 지원)
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name = aws_eks_cluster.main.name # 상위 클러스터 참조
  addon_name   = "aws-ebs-csi-driver"

  service_account_role_arn = aws_iam_role.ebs_csi_driver.arn # iam.tf IRSA 역할

  depends_on = [
    aws_eks_cluster.main,   # 클러스터 준비 후 설치
    aws_eks_node_group.main # node-group.tf 노드 준비 후 설치
  ]

  tags = {
    Name = "${var.cluster_name}-ebs-csi-addon"
  }
}

# CoreDNS addon - DNS 서비스 디스커버리용
resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "coredns"

  depends_on = [
    aws_eks_cluster.main,   # 클러스터 API 준비 후 설치
    aws_eks_node_group.main # 노드에서 실행될 파드
  ]

  tags = {
    Name = "${var.cluster_name}-coredns-addon"
  }
}

# kube-proxy addon - 서비스 네트워크 로드 밸런싱
resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"

  depends_on = [
    aws_eks_cluster.main,   # 클러스터 API 서버 준비
    aws_eks_node_group.main # 각 노드에 DaemonSet 배포
  ]

  tags = {
    Name = "${var.cluster_name}-kube-proxy-addon"
  }
}

# VPC CNI v2 addon - 파드에 VPC IP 할당 (K8s 1.33 성능 개선)
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"

  depends_on = [
    aws_eks_cluster.main,   # 클러스터 CIDR 설정 후
    aws_eks_node_group.main # ENI 관리를 위한 노드 IAM 역할 필요
  ]

  tags = {
    Name = "${var.cluster_name}-vpc-cni-addon"
  }
}