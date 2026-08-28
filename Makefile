# =============================================================================
# EKS Terraform 자동화 Makefile
# =============================================================================
# 사용법:
#   make setup     - 초기 설정 (tfvars 파일 생성)
#   make plan      - Terraform 실행 계획 확인
#   make deploy-all - 배포부터 데모 앱까지 한 번에
#   make kubeconfig - kubectl 설정
#   make status    - 클러스터 상태 확인
#   make destroy   - 리소스 삭제
#   make clean     - 임시 파일 정리
# =============================================================================

.PHONY: help check-tools check-aws setup validate plan deploy deploy-all kubeconfig status \
        test-app app-status app-open app-watch clean-test-app destroy clean \
        cost-note versions cluster-version insights \
        rollback-nodegroup rollback-cluster updates drift

# 기본 변수
CLUSTER_NAME ?= my-study-eks
AWS_REGION ?= ap-northeast-1
TFVARS_FILE = terraform/terraform.tfvars

# AWS CLI v2 는 기본으로 출력을 pager 에 넣는다. 빈 값이면 pager 를 쓰지 않는다.
# https://docs.aws.amazon.com/cli/latest/userguide/cli-usage-pagination.html
export AWS_PAGER :=

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
	@echo "  1. make setup      - 초기 설정"
	@echo "  2. make plan       - 실행 계획 확인"
	@echo "  3. make deploy-all - 배포 + 상태 확인 + 데모 앱까지 한 번에"
	@echo "     make deploy     - 배포만 (확인 프롬프트 있음)"
	@echo ""
	@echo "${GREEN}버전 롤백 검증 순서:${NC}"
	@echo "  1. make versions                        - 지원 버전 확인"
	@echo "  2. tfvars 의 kubernetes_version 을 1.36 으로 변경"
	@echo "  3. make deploy                          - 1.35 → 1.36 업그레이드"
	@echo "  4. make insights                        - 롤백 가능 여부 확인"
	@echo "  5. make rollback-nodegroup VERSION=1.35 - 노드 그룹 먼저 (패턴 A 만)"
	@echo "  6. make rollback-cluster VERSION=1.35   - 컨트롤 플레인"
	@echo "  7. make updates                         - 진행 상태 확인"
	@echo "  8. make drift                           - Terraform 차이 확인"
	@echo ""
	@echo "${RED}검증 후 반드시 make destroy 를 실행하세요${NC}"

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
	@ARN=$$(aws sts get-caller-identity --query Arn --output text 2>/dev/null) || \
		{ echo "${RED}Error: AWS 자격 증명이 설정되지 않았습니다. 'aws configure' 명령을 실행하세요${NC}"; exit 1; }; \
	echo "${GREEN}✓ AWS 계정 확인됨: $$ARN${NC}"

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

deploy: ## EKS 클러스터 배포 (약 15분 소요, 과금 시작)
	@echo "${RED}⚠️  AWS 리소스를 생성합니다. 과금이 시작됩니다.${NC}"
	@cd terraform && terraform plan -out=tfplan
	@echo ""
	@printf "${YELLOW}위 계획대로 배포합니다. 계속하려면 yes 를 입력하세요: ${NC}"; \
	read ans; [ "$$ans" = "yes" ] || { echo "${RED}중단했습니다${NC}"; exit 1; }
	@cd terraform && terraform apply --parallelism=30 tfplan
	@rm -f terraform/tfplan
	@echo "${GREEN}✓ EKS 클러스터 배포가 완료되었습니다${NC}"
	@$(MAKE) kubeconfig
	@$(MAKE) cost-note

deploy-all: setup ## 배포 + 상태 확인 + 버전 확인 + 데모 앱을 한 번에 (검증용)
	@echo "${BLUE}=== 시작 $$(date '+%Y-%m-%d %H:%M:%S') ===${NC}"
	@$(MAKE) deploy
	@$(MAKE) status
	@$(MAKE) cluster-version
	@$(MAKE) test-app
	@echo "${BLUE}=== 완료 $$(date '+%Y-%m-%d %H:%M:%S') ===${NC}"
	@echo "${YELLOW}다음: tfvars 의 kubernetes_version 을 1.36 으로 바꾸고 make deploy${NC}"

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

test-app: ## 데모 앱 배포 (ClusterIP. LoadBalancer 과금 없음)
	@kubectl apply -f k8s-manifests/demo-app.yaml
	@kubectl rollout status deployment/demo-app --timeout=180s
	@$(MAKE) app-status

app-status: ## 데모 앱의 파드가 어느 노드에서 도는지 확인
	@kubectl get pods -l app=demo-app -o wide
	@kubectl get pdb demo-app 2>/dev/null || true

app-open: ## 데모 앱을 로컬 8080 포트로 연결
	@echo "${BLUE}http://localhost:8080 에서 확인하세요. 종료는 Ctrl+C${NC}"
	@kubectl port-forward svc/demo-app 8080:80

app-watch: ## 롤백 중 파드 상태를 실시간 관찰
	@kubectl get pods -l app=demo-app -o wide --watch

clean-test-app: ## 데모 앱 삭제
	@kubectl delete -f k8s-manifests/demo-app.yaml --ignore-not-found

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

# =============================================================================
# 버전 롤백 검증용 타깃
# =============================================================================
# 시나리오: 1.35 로 생성 → 1.36 으로 업그레이드 → 1.35 로 롤백
# 주의: 생성 당시 버전으로는 롤백할 수 없다. 반드시 업그레이드를 거쳐야 한다.
#
# 패턴 A: kubernetes_version 만 바꿔 컨트롤 플레인과 노드를 함께 올린다.
#         롤백할 때 노드 그룹을 먼저 되돌려야 한다.
# 패턴 B: node_group_kubernetes_version 을 1.35 로 고정한 뒤 kubernetes_version 만
#         1.36 으로 올린다. 노드가 N-1 에 머물러 kubelet skew 인사이트가 PASSING 이라
#         롤백은 컨트롤 플레인만 되돌리면 된다. AWS 권장 방식.
# https://docs.aws.amazon.com/eks/latest/best-practices/rollback-cluster-upgrades.html
# =============================================================================

cost-note: ## 현재 구성의 대략적인 시간당 비용 표시
	@echo "${YELLOW}=== 대략적인 시간당 비용 ===${NC}"
	@echo "  EKS 컨트롤 플레인      \$$0.10"
	@echo "  t3.small SPOT x2       ~\$$0.014"
	@echo "  NAT Gateway x1         ~\$$0.045"
	@echo "  합계                   ~\$$0.16/시간"
	@echo "${RED}검증이 끝나면 반드시 make destroy 를 실행하세요${NC}"

versions: ## 사용 가능한 EKS 버전과 지원 상태 확인
	@echo "${BLUE}EKS 클러스터 버전 목록${NC}"
	@aws eks describe-cluster-versions \
		--query 'clusterVersions[].{version:clusterVersion,status:status,eos:endOfStandardSupportDate}' \
		--output table

cluster-version: ## 현재 클러스터와 노드 그룹의 버전 확인
	@CN=$$(cd terraform && terraform output -raw cluster_name 2>/dev/null || echo "$(CLUSTER_NAME)"); \
	echo "${BLUE}컨트롤 플레인${NC}"; \
	aws eks describe-cluster --name $$CN --query 'cluster.{version:version,platform:platformVersion,status:status}' --output table; \
	echo "${BLUE}노드 그룹${NC}"; \
	for NG in $$(aws eks list-nodegroups --cluster-name $$CN --query 'nodegroups[]' --output text); do \
		aws eks describe-nodegroup --cluster-name $$CN --nodegroup-name $$NG \
			--query 'nodegroup.{name:nodegroupName,version:version,release:releaseVersion,status:status}' --output table; \
	done

insights: ## 롤백 가능 여부 인사이트 확인 (업그레이드 후 7일간만 표시)
	@CN=$$(cd terraform && terraform output -raw cluster_name 2>/dev/null || echo "$(CLUSTER_NAME)"); \
	echo "${BLUE}ROLLBACK_READINESS 인사이트${NC}"; \
	aws eks list-insights --cluster-name $$CN \
		--filter '{"categories": ["ROLLBACK_READINESS"]}' \
		--query 'insights[].{name:name,status:insightStatus.status,reason:insightStatus.reason}' \
		--output table

rollback-nodegroup: ## 노드 그룹만 이전 버전으로 롤백 (VERSION=1.35 필요)
	@test -n "$(VERSION)" || { echo "${RED}VERSION 을 지정하세요. 예: make rollback-nodegroup VERSION=1.35${NC}"; exit 1; }
	@echo "${BLUE}=== 노드 그룹 롤백 시작 $$(date '+%Y-%m-%d %H:%M:%S') ===${NC}"
	@CN=$$(cd terraform && terraform output -raw cluster_name 2>/dev/null || echo "$(CLUSTER_NAME)"); \
	for NG in $$(aws eks list-nodegroups --cluster-name $$CN --query 'nodegroups[]' --output text); do \
		echo "${BLUE}$$NG 를 $(VERSION) 으로 롤백${NC}"; \
		aws eks update-nodegroup-version --cluster-name $$CN --nodegroup-name $$NG \
			--kubernetes-version $(VERSION); \
	done

rollback-cluster: ## 컨트롤 플레인을 이전 버전으로 롤백 (VERSION=1.35 필요)
	@test -n "$(VERSION)" || { echo "${RED}VERSION 을 지정하세요. 예: make rollback-cluster VERSION=1.35${NC}"; exit 1; }
	@echo "${RED}⚠️  컨트롤 플레인을 $(VERSION) 으로 롤백합니다. 노드 그룹을 먼저 롤백했는지 확인하세요.${NC}"
	@printf "${YELLOW}계속하려면 yes 를 입력하세요: ${NC}"; \
	read ans; [ "$$ans" = "yes" ] || { echo "${RED}중단했습니다${NC}"; exit 1; }
	@echo "${BLUE}=== 컨트롤 플레인 롤백 시작 $$(date '+%Y-%m-%d %H:%M:%S') ===${NC}"
	@CN=$$(cd terraform && terraform output -raw cluster_name 2>/dev/null || echo "$(CLUSTER_NAME)"); \
	aws eks update-cluster-version --name $$CN --kubernetes-version $(VERSION)
	@echo "${YELLOW}응답의 type 이 VersionRollback 이면 롤백으로 처리된 것입니다${NC}"
	@echo "${BLUE}진행 상황은 make updates 로 확인하세요${NC}"

updates: ## 클러스터 업데이트 이력과 진행 상태 확인
	@CN=$$(cd terraform && terraform output -raw cluster_name 2>/dev/null || echo "$(CLUSTER_NAME)"); \
	for ID in $$(aws eks list-updates --name $$CN --query 'updateIds[]' --output text); do \
		aws eks describe-update --name $$CN --update-id $$ID \
			--query 'update.{id:id,type:type,status:status,created:createdAt}' --output table; \
	done

drift: ## 롤백 후 Terraform 과 실제 상태의 차이 확인
	@echo "${BLUE}terraform plan 으로 drift 를 확인합니다${NC}"
	@cd terraform && terraform plan -detailed-exitcode || \
		echo "${YELLOW}차이가 있습니다. kubernetes_version 을 실제 버전에 맞추세요${NC}"

clean: ## 임시 파일 정리 (lock 파일은 재현성을 위해 유지)
	@echo "${BLUE}임시 파일을 정리합니다...${NC}"
	@rm -f terraform/terraform.tfstate.backup
	@rm -f terraform/tfplan
	@echo "${GREEN}✓ 임시 파일이 정리되었습니다${NC}"
	@echo "${YELLOW}참고: .terraform.lock.hcl 은 provider 버전 고정용이라 삭제하지 않습니다${NC}"


# 기본 타겟
.DEFAULT_GOAL := help