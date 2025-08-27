# =============================================================================
# 보안 그룹 설정
# =============================================================================
# 이 파일은 EKS 클러스터와 워커 노드의 보안 그룹을 정의합니다.
# - EKS 클러스터용 보안 그룹 (컨트롤 플레인)
# - 워커 노드용 보안 그룹
# - ALB/NLB용 보안 그룹
# - 최소 권한 원칙에 따른 트래픽 제어
# - 노드 간 통신 및 클러스터-노드 간 통신 허용
# =============================================================================

# EKS 클러스터용 보안 그룹
# 컨트롤 플레인과 워커 노드 간의 통신을 제어합니다
resource "aws_security_group" "eks_cluster" {
  name_prefix = "${var.cluster_name}-cluster-sg"
  vpc_id      = aws_vpc.main.id

  description = "Security group for EKS cluster control plane"

  tags = {
    Name = "${var.cluster_name}-cluster-sg"
  }
}

# 클러스터 보안 그룹 아웃바운드 규칙
# 컨트롤 플레인에서 워커 노드로의 모든 통신 허용
resource "aws_security_group_rule" "cluster_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1" # 모든 프로토콜
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.eks_cluster.id
  description       = "Allow all outbound traffic from cluster"
}

# 워커 노드에서 클러스터로의 HTTPS 통신 허용 (포트 443)
resource "aws_security_group_rule" "cluster_ingress_workstation_https" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_nodes.id
  security_group_id        = aws_security_group.eks_cluster.id
  description              = "Allow workstation to communicate with the cluster API server"
}

# EKS 워커 노드용 보안 그룹
# 워커 노드(EC2 인스턴스) 간의 통신과 외부와의 통신을 제어합니다
resource "aws_security_group" "eks_nodes" {
  name_prefix = "${var.cluster_name}-node-sg"
  vpc_id      = aws_vpc.main.id

  description = "Security group for all nodes in the cluster"

  tags = {
    Name                                        = "${var.cluster_name}-node-sg"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# 워커 노드 간 통신 허용 (자기 자신과의 통신)
# 파드 간 통신과 서비스 디스커버리를 위해 필요합니다
resource "aws_security_group_rule" "nodes_internal" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  source_security_group_id = aws_security_group.eks_nodes.id
  security_group_id        = aws_security_group.eks_nodes.id
  description              = "Allow nodes to communicate with each other"
}

# 클러스터에서 워커 노드로의 통신 허용
resource "aws_security_group_rule" "nodes_cluster_inbound" {
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_cluster.id
  security_group_id        = aws_security_group.eks_nodes.id
  description              = "Allow worker Kubelets and pods to receive communication from the cluster control plane"
}

# HTTPS (443) 포트로 클러스터와의 통신 허용
resource "aws_security_group_rule" "nodes_cluster_inbound_https" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_cluster.id
  security_group_id        = aws_security_group.eks_nodes.id
  description              = "Allow pods running extension API servers on port 443 to receive communication from cluster control plane"
}

# SSH 접근 허용 (관리 목적)
# 보안상 특정 IP에서만 접근하도록 제한하는 것이 좋습니다
resource "aws_security_group_rule" "nodes_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr] # VPC 내에서만 SSH 접근 허용
  security_group_id = aws_security_group.eks_nodes.id
  description       = "Allow SSH access to worker nodes from VPC"
}

# 워커 노드의 모든 아웃바운드 트래픽 허용
# 인터넷 접근, 컨테이너 이미지 다운로드, 외부 API 호출 등을 위해 필요
resource "aws_security_group_rule" "nodes_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.eks_nodes.id
  description       = "Allow all outbound traffic from worker nodes"
}

# 로드 밸런서용 보안 그룹 (선택적)
# 쿠버네티스 서비스 타입이 LoadBalancer일 때 사용됩니다
resource "aws_security_group" "alb" {
  name_prefix = "${var.cluster_name}-alb-sg"
  vpc_id      = aws_vpc.main.id

  description = "Security group for Application Load Balancer"

  tags = {
    Name = "${var.cluster_name}-alb-sg"
  }
}

# ALB 인바운드 HTTP (80) 트래픽 허용
resource "aws_security_group_rule" "alb_http_inbound" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
  description       = "Allow HTTP traffic to ALB"
}

# ALB 인바운드 HTTPS (443) 트래픽 허용
resource "aws_security_group_rule" "alb_https_inbound" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
  description       = "Allow HTTPS traffic to ALB"
}

# ALB에서 워커 노드로의 트래픽 허용
resource "aws_security_group_rule" "alb_to_nodes" {
  type                     = "egress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_nodes.id
  security_group_id        = aws_security_group.alb.id
  description              = "Allow ALB to communicate with worker nodes"
}

# 워커 노드에서 ALB로부터의 트래픽 허용
resource "aws_security_group_rule" "nodes_from_alb" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.eks_nodes.id
  description              = "Allow traffic from ALB to worker nodes"
}