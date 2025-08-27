#!/bin/bash

# EKS 배포 검증 스크립트
set -e

echo "🔍 EKS 클러스터 배포 검증 시작..."

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 함수 정의
check_command() {
    if command -v $1 &> /dev/null; then
        echo -e "${GREEN}✓${NC} $1 is installed"
    else
        echo -e "${RED}✗${NC} $1 is not installed"
        exit 1
    fi
}

# 1. 필수 도구 확인
echo -e "\n${BLUE}=== 필수 도구 확인 ===${NC}"
check_command terraform
check_command aws
check_command kubectl
check_command jq

# 2. AWS 인증 확인
echo -e "\n${BLUE}=== AWS 인증 확인 ===${NC}"
if aws sts get-caller-identity &> /dev/null; then
    echo -e "${GREEN}✓${NC} AWS credentials configured"
    aws sts get-caller-identity --output table
else
    echo -e "${RED}✗${NC} AWS credentials not configured"
    exit 1
fi

# 3. Terraform 초기화 및 검증
echo -e "\n${BLUE}=== Terraform 검증 ===${NC}"
cd terraform
terraform init -input=false
echo -e "${GREEN}✓${NC} Terraform initialized"

terraform validate
echo -e "${GREEN}✓${NC} Terraform configuration valid"

terraform fmt -check=true
echo -e "${GREEN}✓${NC} Terraform formatting correct"

cd ..

# 4. 클러스터 상태 확인 (배포된 경우)
echo -e "\n${BLUE}=== 클러스터 상태 확인 ===${NC}"
if kubectl cluster-info &> /dev/null; then
    echo -e "${GREEN}✓${NC} Connected to EKS cluster"
    
    # 노드 상태 확인
    echo -e "\n${YELLOW}Cluster Nodes:${NC}"
    kubectl get nodes -o wide
    
    # 시스템 파드 상태 확인
    echo -e "\n${YELLOW}System Pods:${NC}"
    kubectl get pods -n kube-system
    
    # 애드온 상태 확인
    echo -e "\n${YELLOW}EKS Addons:${NC}"
    if command -v aws &> /dev/null; then
        CLUSTER_NAME=$(terraform -chdir=terraform output -raw cluster_name 2>/dev/null || echo "unknown")
        if [ "$CLUSTER_NAME" != "unknown" ]; then
            aws eks describe-cluster --name $CLUSTER_NAME --query 'cluster.status' --output text
        fi
    fi
else
    echo -e "${YELLOW}⚠${NC} Not connected to EKS cluster (배포되지 않았거나 kubeconfig 설정 필요)"
fi

echo -e "\n${GREEN}🎉 검증 완료!${NC}"