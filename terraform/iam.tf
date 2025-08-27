# =============================================================================
# IAM 역할 및 정책 설정
# =============================================================================
# 이 파일은 EKS 클러스터와 워커 노드의 IAM 권한을 정의합니다.
# - EKS 클러스터용 IAM 역할 (컨트롤 플레인)
# - EKS 노드 그룹용 IAM 역할 (워커 노드)
# - EBS CSI 드라이버용 IAM 역할 (IRSA)
# - OIDC Identity Provider (서비스 어카운트 연동)
# - 필수 AWS 관리형 정책 연결
# =============================================================================

# EKS 컨트롤 플레인이 AWS API 호출에 사용할 IAM 역할 - eks.tf에서 참조
resource "aws_iam_role" "eks_cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-cluster-role"
  }
}

# EKS 컨트롤 플레인 관리 권한 - eks.tf 리소스에서 depends_on으로 참조
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# EKS 노드 그룹 EC2 인스턴스가 사용할 IAM 역할 - node-group.tf에서 참조
resource "aws_iam_role" "eks_node_group" {
  name = "${var.cluster_name}-node-group-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-node-group-role"
  }
}

# EC2 인스턴스가 EKS 노드로 작동하는 데 필요한 권한 - node-group.tf depends_on에서 참조
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_group.name
}

# VPC CNI 플러그인이 ENI 관리에 사용하는 권한 - 파드 IP 할당 필수
resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_group.name
}

# ECR에서 컨테이너 이미지 다운로드에 필요한 권한
resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_group.name
}

# EBS CSI 드라이버 애드온이 PV/PVC 생성에 사용 - eks.tf 애드온에서 참조
resource "aws_iam_role" "ebs_csi_driver" {
  name = "${var.cluster_name}-ebs-csi-driver-role"

  # IRSA(IAM Roles for Service Accounts)를 통한 서비스 어카운트 인증
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn # OIDC 프로바이더 참조
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-ebs-csi-driver-role"
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_driver.name
}

# IRSA(IAM Roles for Service Accounts) 설정용 OIDC 프로바이더
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer # EKS 클러스터 OIDC URL
}

# 쿠버네티스 ServiceAccount와 IAM Role 매핑을 위한 OIDC 프로바이더
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer # EKS 클러스터에서 생성된 OIDC

  tags = {
    Name = "${var.cluster_name}-eks-oidc"
  }
}