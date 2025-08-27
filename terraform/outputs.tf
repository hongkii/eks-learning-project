# 주요 클러스터 정보 출력

# EKS 클러스터 정보
output "cluster_id" {
  description = "EKS 클러스터 ID"
  value       = aws_eks_cluster.main.id
}

output "cluster_arn" {
  description = "EKS 클러스터 ARN (Amazon Resource Name)"
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "EKS 클러스터 API 엔드포인트 URL"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "EKS 클러스터 쿠버네티스 버전"
  value       = aws_eks_cluster.main.version
}

# 보안 관련 정보
output "cluster_security_group_id" {
  description = "EKS 클러스터에 연결된 보안 그룹 ID"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "cluster_certificate_authority_data" {
  description = "EKS 클러스터 인증서 권한 데이터 (base64 인코딩)"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

# 서비스 어카운트 IAM 역할 연동을 위한 OIDC
output "cluster_oidc_issuer_url" {
  description = "EKS 클러스터 OIDC identity provider URL"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN"
  value       = aws_iam_openid_connect_provider.eks.arn
}

# 노드 그룹 정보
output "node_group_arn" {
  description = "EKS 노드 그룹 ARN"
  value       = aws_eks_node_group.main.arn
}

output "node_group_status" {
  description = "EKS 노드 그룹 상태"
  value       = aws_eks_node_group.main.status
}

# 네트워킹 정보
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "프라이빗 서브넷 ID 목록"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID 목록"
  value       = aws_subnet.public[*].id
}

# 보안 그룹
output "node_security_group_id" {
  description = "워커 노드 보안 그룹 ID"
  value       = aws_security_group.eks_nodes.id
}

output "alb_security_group_id" {
  description = "ALB 보안 그룹 ID"
  value       = aws_security_group.alb.id
}

# kubectl 설정
output "kubectl_config_command" {
  description = "kubectl 설정을 위한 AWS CLI 명령어"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${var.cluster_name}"
}

# 추가 클러스터 정보
output "cluster_region" {
  description = "EKS 클러스터가 배포된 AWS 리전"
  value       = var.aws_region
}

# CloudWatch 로그
output "cloudwatch_log_group_name" {
  description = "EKS 클러스터 로그가 저장되는 CloudWatch 로그 그룹 이름"
  value       = aws_cloudwatch_log_group.eks_cluster.name
}

# 리소스 태그
output "resource_tags" {
  description = "리소스에 적용된 태그 정보"
  value = {
    Project     = "EKS-Study"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Purpose     = "Learning-K8s"
  }
}