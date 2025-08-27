# =============================================================================
# EKS Terraform 자동화 Makefile
# =============================================================================
# 사용법:
#   make setup     - 초기 설정 (tfvars 파일 생성)
#   make plan      - Terraform 실행 계획 확인
#   make deploy    - EKS 클러스터 배포
#   make kubeconfig - kubectl 설정
#   make status    - 클러스터 상태 확인
#   make destroy   - 리소스 삭제
#   make clean     - 임시 파일 정리
# =============================================================================

.PHONY: help setup validate plan deploy kubeconfig status test-app destroy clean all

# 기본 변수
CLUSTER_NAME ?= my-study-eks
AWS_REGION ?= ap-northeast-1
TFVARS_FILE = terraform/terraform.tfvars

# 색상 코드
RED = \033[0;31m
GREEN = \033[0;32m
YELLOW = \033[0;33m
BLUE = \033[0;34m
NC = \033[0m # No Color

help: ## 사용 가능한 명령어 표시
	@echo "${BLUE}EKS Terraform 자동화 도구${NC}"
	@echo ""
	@echo "${GREEN}사용 가능한 명령어:${NC}"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  ${YELLOW}%-15s${NC} %s\n", $$1, $$2}'
	@echo ""
	@echo "${GREEN}배포 순서:${NC}"
	@echo "  1. make setup     - 초기 설정"
	@echo "  2. make plan      - 실행 계획 확인"
	@echo "  3. make deploy    - 클러스터 배포"
	@echo "  4. make kubeconfig - kubectl 설정"
	@echo "  5. make status    - 상태 확인"

check-tools: ## 필수 도구 설치 확인
	@echo "${BLUE}필수 도구 설치 확인 중...${NC}"
	@command -v terraform >/dev/null 2>&1 || { echo "${RED}Error: terraform이 설치되지 않았습니다${NC}"; exit 1; }
	@command -v aws >/dev/null 2>&1 || { echo "${RED}Error: aws cli가 설치되지 않았습니다${NC}"; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo "${RED}Error: kubectl이 설치되지 않았습니다${NC}"; exit 1; }
	@echo "${GREEN}✓ 모든 필수 도구가 설치되어 있습니다${NC}"
	@echo ""
	@echo "${BLUE}버전 정보:${NC}"
	@terraform version | head -1
	@aws --version
	@kubectl version --client=true --short 2>/dev/null || kubectl version --client

check-aws: ## AWS 계정 및 권한 확인
	@echo "${BLUE}AWS 계정 확인 중...${NC}"
	@aws sts get-caller-identity >/dev/null 2>&1 || { echo "${RED}Error: AWS 자격 증명이 설정되지 않았습니다. 'aws configure' 명령을 실행하세요${NC}"; exit 1; }
	@echo "${GREEN}✓ AWS 계정 확인됨${NC}"
	@aws sts get-caller-identity

setup: check-tools check-aws ## 초기 설정 (terraform.tfvars 파일 생성)
	@echo "${BLUE}초기 설정을 시작합니다...${NC}"
	@if [ ! -f $(TFVARS_FILE) ]; then \
		echo "${YELLOW}terraform.tfvars 파일이 없습니다. 생성 중...${NC}"; \
		cp terraform.tfvars.example $(TFVARS_FILE); \
		echo "${GREEN}✓ terraform.tfvars 파일이 생성되었습니다${NC}"; \
		echo "${YELLOW}⚠️  terraform/terraform.tfvars 파일을 편집하여 실제 값을 입력하세요${NC}"; \
		echo "   - cluster_name: 클러스터 이름"; \
		echo "   - ec2_key_pair_name: 키 페어 이름 (빈 문자열로 설정하면 SSH 비활성화)"; \
	else \
		echo "${GREEN}✓ terraform.tfvars 파일이 이미 존재합니다${NC}"; \
	fi
	@cd terraform && terraform init
	@echo "${GREEN}✓ 초기 설정이 완료되었습니다${NC}"

validate: ## Terraform 설정 파일 유효성 검사
	@echo "${BLUE}Terraform 설정 유효성 검사 중...${NC}"
	@cd terraform && terraform validate
	@cd terraform && terraform fmt -check=true -diff=true
	@echo "${GREEN}✓ 설정 파일이 유효합니다${NC}"

plan: setup validate ## Terraform 실행 계획 확인
	@echo "${BLUE}Terraform 실행 계획을 확인합니다...${NC}"
	@cd terraform && terraform plan
	@echo "${GREEN}✓ 실행 계획 확인이 완료되었습니다${NC}"
	@echo "${YELLOW}계획을 검토한 후 'make deploy' 명령으로 배포하세요${NC}"

deploy: ## EKS 클러스터 배포 (약 10-15분 소요)
	@echo "${BLUE}EKS 클러스터 배포를 시작합니다... (10-15분 소요)${NC}"
	@cd terraform && terraform apply --parallelism=30 -auto-approve
	@echo "${GREEN}✓ EKS 클러스터 배포가 완료되었습니다${NC}"
	@$(MAKE) kubeconfig

kubeconfig: ## kubectl 설정 업데이트
	@echo "${BLUE}kubectl 설정을 업데이트합니다...${NC}"
	@CLUSTER_NAME=$$(cd terraform && terraform output -raw cluster_name 2>/dev/null || echo "$(CLUSTER_NAME)"); \
	AWS_REGION=$$(cd terraform && terraform output -raw cluster_region 2>/dev/null || echo "$(AWS_REGION)"); \
	aws eks update-kubeconfig --region $$AWS_REGION --name $$CLUSTER_NAME
	@echo "${GREEN}✓ kubectl 설정이 업데이트되었습니다${NC}"

status: ## 클러스터 상태 확인
	@echo "${BLUE}클러스터 상태를 확인합니다...${NC}"
	@echo ""
	@echo "${GREEN}=== 클러스터 정보 ===${NC}"
	@kubectl cluster-info 2>/dev/null || echo "${RED}클러스터에 연결할 수 없습니다${NC}"
	@echo ""
	@echo "${GREEN}=== 노드 상태 ===${NC}"
	@kubectl get nodes -o wide 2>/dev/null || echo "${RED}노드 정보를 가져올 수 없습니다${NC}"
	@echo ""
	@echo "${GREEN}=== 시스템 파드 ===${NC}"
	@kubectl get pods -n kube-system 2>/dev/null || echo "${RED}시스템 파드 정보를 가져올 수 없습니다${NC}"

test-app: ## 테스트 애플리케이션 배포
	@echo "${BLUE}테스트 nginx 애플리케이션을 배포합니다...${NC}"
	@kubectl create deployment test-nginx --image=nginx --replicas=2 2>/dev/null || echo "${YELLOW}deployment가 이미 존재합니다${NC}"
	@kubectl expose deployment test-nginx --port=80 --type=LoadBalancer 2>/dev/null || echo "${YELLOW}service가 이미 존재합니다${NC}"
	@echo "${GREEN}✓ 테스트 애플리케이션이 배포되었습니다${NC}"
	@echo "${YELLOW}LoadBalancer 생성을 기다리는 중... (2-3분 소요)${NC}"
	@kubectl get service test-nginx --watch 2>/dev/null &
	@echo "${BLUE}서비스 상태를 확인하려면 'kubectl get svc test-nginx'를 실행하세요${NC}"

clean-test-app: ## 테스트 애플리케이션 삭제
	@echo "${BLUE}테스트 애플리케이션을 삭제합니다...${NC}"
	@kubectl delete service test-nginx 2>/dev/null || echo "${YELLOW}service가 존재하지 않습니다${NC}"
	@kubectl delete deployment test-nginx 2>/dev/null || echo "${YELLOW}deployment가 존재하지 않습니다${NC}"
	@echo "${GREEN}✓ 테스트 애플리케이션이 삭제되었습니다${NC}"

destroy: clean-test-app ## 모든 리소스 삭제
	@echo "${RED}⚠️ 모든 AWS 리소스를 삭제합니다!${NC}"
	@echo "${BLUE}LoadBalancer 서비스 확인 및 삭제 중...${NC}"
	@kubectl get services --all-namespaces -o json | jq -r '.items[] | select(.spec.type=="LoadBalancer") | "\(.metadata.namespace) \(.metadata.name)"' | while read ns name; do kubectl delete service $$name -n $$ns 2>/dev/null || true; done
	@echo "${BLUE}PersistentVolume 삭제 중...${NC}"
	@kubectl delete pv --all 2>/dev/null || true
	@echo "${BLUE}Terraform으로 인프라 삭제 중... (10-15분 소요)${NC}"
	@cd terraform && terraform destroy --parallelism=30 -auto-approve
	@echo "${BLUE}kubeconfig에서 클러스터 정보 정리 중...${NC}"
	@echo "클러스터 이름: $(CLUSTER_NAME)"; \
	kubectl config get-contexts -o name | grep $(CLUSTER_NAME) | xargs -r kubectl config delete-context 2>/dev/null || true; \
	kubectl config get-clusters | grep $(CLUSTER_NAME) | awk '{print $$1}' | xargs -r kubectl config delete-cluster 2>/dev/null || true
	@echo "${GREEN}✓ 모든 리소스가 삭제되었습니다${NC}"

clean: ## 임시 파일 정리
	@echo "${BLUE}임시 파일을 정리합니다...${NC}"
	@rm -f terraform/terraform.tfstate.backup
	@rm -f terraform/.terraform.lock.hcl
	@echo "${GREEN}✓ 임시 파일이 정리되었습니다${NC}"

all: setup plan deploy status ## 전체 배포 프로세스 실행
	@echo "${GREEN}✓ 전체 배포가 완료되었습니다${NC}"
	@echo ""
	@echo "${BLUE}다음 단계:${NC}"
	@echo "  1. make status        - 클러스터 상태 확인"
	@echo "  2. make test-app      - 테스트 앱 배포"
	@echo "  3. kubectl get nodes  - 노드 확인"
	@echo "  4. kubectl get svc    - 서비스 확인"

# 기본 타겟
.DEFAULT_GOAL := help