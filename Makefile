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

.PHONY: help check-tools check-aws setup validate plan deploy kubeconfig status \
        deploy-all _deploy-all upgrade _upgrade session destroy _destroy \
        test-app app-status app-open app-watch monitor probe clean-test-app clean-eni clean log log-merge \
        cost-note versions cluster-version addons insights \
        addons-for addon-set rollback-try-apply \
        rollback-nodegroup rollback-cluster wait-nodegroup rollback-rest _rollback-rest \
        _rollback-try-apply \
        rollback-a _rollback-a rollback-b _rollback-b \
        updates drift \
        gitops-init gitops-plan _gitops-plan gitops-apply _gitops-apply gitops-destroy _gitops-destroy \
        argocd-ui argocd-password argocd-apps

# 개인 설정은 Makefile.local 에 둔다. gitignore 대상이라 저장소에는 올라가지 않는다.
# 예: AWS_PROFILE = my-profile
-include Makefile.local

# 기본 변수
CLUSTER_NAME ?= my-study-eks
AWS_REGION ?= ap-northeast-1
TFVARS_FILE = terraform/terraform.tfvars
LOG_DIR = logs
# 실행한 날짜별로 나눈다. RUN_DATE 를 넘기면 과거 폴더를 다룰 수 있다.
RUN_DATE ?= $(shell date +%Y%m%d)
RUN_DIR = $(LOG_DIR)/$(RUN_DATE)
# 실행할 때마다 덮어쓴다. 확장자가 .log 가 아니라서 합칠 대상에는 포함되지 않는다.
MERGED = $(RUN_DIR)/merged.txt

# 1 이면 배포와 롤백의 yes 확인을 건너뛴다. 기본은 확인을 받는다.
AUTO_APPROVE ?= 0

# 모니터 스냅샷 간격(초).
INTERVAL ?= 15

# Makefile.local 에서 지정했으면 모든 하위 명령이 같은 프로파일을 쓴다.
ifneq ($(strip $(AWS_PROFILE)),)
export AWS_PROFILE
endif

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
	@# -h: Makefile.local 을 include 하면 MAKEFILE_LIST 가 여러 개라 파일명이 붙는다
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  ${YELLOW}%-20s${NC} %s\n", $$1, $$2}'
	@echo ""
	@echo "${GREEN}배포 순서:${NC}"
	@echo "  1. make plan       - 실행 계획 확인"
	@echo "  2. make deploy-all - 배포 + 상태 + 버전 + 애드온 + 데모 앱까지 한 번에"
	@echo ""
	@echo "${GREEN}패턴 A (컨트롤 플레인과 노드를 함께 올림):${NC}"
	@echo "  1. tfvars: kubernetes_version = \"1.36\""
	@echo "  2. make upgrade                  - 1 apply 로 클러스터·노드·애드온 갱신"
	@echo "  3. tfvars: kubernetes_version = \"1.35\" 로 되돌림"
	@echo "  4. make rollback-try-apply       - apply 로는 안 되는 것을 확인 (선택)"
	@echo "  5. make rollback-a VERSION=1.35  - 노드 -> 애드온 -> 컨트롤 플레인"
	@echo ""
	@echo "${GREEN}패턴 B (컨트롤 플레인만 먼저 올리고 bake):${NC}"
	@echo "  1. tfvars: node_group_kubernetes_version = \"1.35\" 추가, kubernetes_version = \"1.36\""
	@echo "  2. make upgrade                  - 컨트롤 플레인만"
	@echo "  3. tfvars: kubernetes_version = \"1.35\" 로 되돌림"
	@echo "  4. make rollback-b VERSION=1.35  - 애드온 -> 컨트롤 플레인"
	@echo ""
	@echo "${GREEN}애드온:${NC}"
	@echo "  업그레이드는 Terraform 이 kubernetes_version 에 맞춰 1 apply 로 처리합니다"
	@echo "  롤백은 노드 그룹 -> 애드온 -> 컨트롤 플레인 순서가 강제되어 apply 로는 불가능합니다"
	@echo "  make addons-for VERSION=1.35  - 해당 버전의 기본 애드온 버전 확인"
	@echo ""
	@echo "${GREEN}옵션:${NC}"
	@echo "  make log T=insights        - 임의 타깃을 logs/ 에 기록하며 실행"
	@echo "  make log-merge             - 합본 수동 갱신 (log 실행 시 자동으로 돌아감)"
	@echo "  make deploy AUTO_APPROVE=1 - yes 확인 생략"
	@echo "  ${YELLOW}롤백 관찰용으로 다른 터미널에서 make app-watch 를 띄워두세요${NC}"
	@echo ""
	@echo "${YELLOW}검증이 끝나면 make destroy 로 정리하세요${NC}"

log: ## 임의의 타깃을 logs/ 에 기록하며 실행. 예: make log T=insights
	@test -n "$(T)" || { echo "${RED}T 를 지정하세요. 예: make log T=insights${NC}"; exit 1; }
	@mkdir -p $(RUN_DIR)
	@NAME="$(N)"; \
	[ -n "$$NAME" ] || NAME=$$(echo "$(T)" | tr ' =/' '---'); \
	STAMP=$$(date '+%Y%m%d-%H%M%S'); \
	LOG=$(RUN_DIR)/$$NAME-$$STAMP.log; \
	export TF_CLI_ARGS_init=-no-color TF_CLI_ARGS_validate=-no-color \
	       TF_CLI_ARGS_plan=-no-color TF_CLI_ARGS_apply=-no-color TF_CLI_ARGS_destroy=-no-color; \
	if [ -n "$$AWS_PROFILE" ]; then \
		CREDS=$$(aws configure export-credentials --format env 2>&1) || \
			{ echo "${RED}자격 증명을 가져오지 못했습니다. make session 을 먼저 실행하세요${NC}"; echo "$$CREDS"; exit 1; }; \
		eval "$$CREDS"; unset AWS_PROFILE; \
		echo "${BLUE}세션 만료: $$AWS_CREDENTIAL_EXPIRATION${NC}"; \
	fi; \
	set -o pipefail; \
	if [ "$(MONITOR)" = "1" ]; then \
		CN=$$(cd terraform && terraform output -raw cluster_name 2>/dev/null || echo "$(CLUSTER_NAME)"); \
		MON=$(RUN_DIR)/$$NAME-monitor-$$STAMP.log; \
		CLUSTER=$$CN INTERVAL=$(INTERVAL) ./scripts/monitor.sh > $$MON 2>&1 & \
		MPID=$$!; \
		trap 'kill '"$$MPID"' 2>/dev/null' EXIT INT TERM; \
		echo "${BLUE}모니터 시작 (PID $$MPID, $(INTERVAL)초 간격) -> $$MON${NC}"; \
		$(MAKE) $(T) 2>&1 | while IFS= read -r l; do printf '[%s] %s\n' "$$(date '+%H:%M:%S')" "$$l"; done | tee $$LOG; \
	else \
		$(MAKE) $(T) 2>&1 | tee $$LOG; \
	fi; \
	RC=$$?; \
	perl -pi -e 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\r$$//' $$LOG; \
	echo "${GREEN}로그: $$LOG${NC}"; \
	$(MAKE) --no-print-directory log-merge >/dev/null 2>&1 || true; \
	echo "${GREEN}합본: $(MERGED)${NC}"; \
	exit $$RC

log-merge: ## 그날 폴더의 로그를 실행 시각 순으로 merged.txt 하나에 합침. RUN_DATE 로 과거 지정 가능
	@ls -1 $(RUN_DIR)/*.log >/dev/null 2>&1 || { echo "${RED}$(RUN_DIR) 에 로그가 없습니다${NC}"; exit 1; }
	@{ \
		echo "EKS version rollback verification"; \
		echo "merged at $$(date '+%Y-%m-%d %H:%M:%S %z')"; \
	} > $(MERGED); \
	for f in $$(ls -1tr $(RUN_DIR)/*.log); do \
		{ \
			echo ""; \
			echo "================================================================"; \
			echo "== $$(basename $$f)"; \
			echo "================================================================"; \
			echo ""; \
		} >> $(MERGED); \
		cat "$$f" >> $(MERGED); \
	done
	@echo "${BLUE}포함된 로그:${NC}"
	@ls -1tr $(RUN_DIR)/*.log | sed 's|^|  |'
	@echo "${GREEN}합본: $(MERGED)${NC}"

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

session: ## MFA 세션 확보. 파이프 밖에서 먼저 실행해 코드 입력을 받는다
	@echo "${BLUE}AWS 세션을 확인합니다$(if $(strip $(AWS_PROFILE)), (profile: $(AWS_PROFILE)),)...${NC}"
	@aws sts get-caller-identity --query Arn --output text
	@# Terraform 은 MFA 프롬프트를 직접 띄우지 못한다. 캐시된 세션에서 임시 자격 증명을
	@# 꺼내 환경변수로 넘기므로, 여기서 만료 시각을 미리 확인해 둔다.
	@if [ -n "$$AWS_PROFILE" ]; then \
		EXP=$$(aws configure export-credentials --format env | sed -n 's/^export AWS_CREDENTIAL_EXPIRATION=//p'); \
		echo "${GREEN}세션 만료: $$EXP${NC}"; \
	fi

check-aws: ## AWS 계정 및 EKS API 호출 가능 여부 확인
	@echo "${BLUE}AWS 계정 확인 중...${NC}"
	@ARN=$$(aws sts get-caller-identity --query Arn --output text 2>/dev/null) || \
		{ echo "${RED}Error: AWS 자격 증명이 설정되지 않았습니다. 'aws configure' 명령을 실행하세요${NC}"; exit 1; }; \
	echo "${GREEN}✓ AWS 계정 확인됨: $$ARN${NC}"
	@# get-caller-identity 는 항상 허용되므로 실제 권한을 따로 확인한다.
	@# MFA 를 요구하는 정책이 걸린 계정에서는 여기서 걸러진다.
	@aws eks list-clusters --query 'clusters' --output text >/dev/null 2>&1 || { \
		echo "${RED}Error: EKS API 호출이 거부되었습니다${NC}"; \
		echo "${YELLOW}  MFA 세션이 필요한 계정일 수 있습니다. 프로파일을 지정하고 다시 실행하세요:${NC}"; \
		echo "    export AWS_PROFILE=<mfa 설정된 프로파일>"; \
		echo "    aws sts get-caller-identity"; \
		exit 1; }
	@echo "${GREEN}✓ EKS API 호출 가능${NC}"

setup: check-tools check-aws ## 초기 설정 (terraform.tfvars 파일 생성)
	@echo "${BLUE}초기 설정을 시작합니다...${NC}"
	@if [ ! -f $(TFVARS_FILE) ]; then \
		echo "${YELLOW}terraform.tfvars 파일이 없습니다. 생성 중...${NC}"; \
		cp terraform.tfvars.example $(TFVARS_FILE); \
		echo "${GREEN}✓ terraform.tfvars 파일이 생성되었습니다${NC}"; \
		echo "${YELLOW}terraform/terraform.tfvars 를 편집해 값을 입력하세요${NC}"; \
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

deploy: ## EKS 클러스터 배포 (약 15분 소요). AUTO_APPROVE=1 로 확인 생략
	@echo "${BLUE}AWS 리소스를 생성합니다${NC}"
	@cd terraform && terraform plan -out=tfplan
	@echo ""
	@if [ "$(AUTO_APPROVE)" = "1" ]; then \
		echo "${BLUE}확인 없이 진행합니다 (AUTO_APPROVE=1)${NC}"; \
	else \
		printf "${YELLOW}위 계획대로 배포합니다. 계속하려면 yes 를 입력하세요: ${NC}"; \
		read ans; [ "$$ans" = "yes" ] || { echo "${RED}중단했습니다${NC}"; exit 1; }; \
	fi
	@cd terraform && terraform apply --parallelism=30 tfplan
	@rm -f terraform/tfplan
	@echo "${GREEN}✓ EKS 클러스터 배포가 완료되었습니다${NC}"
	@$(MAKE) kubeconfig
	@$(MAKE) cost-note

deploy-all: session ## 배포부터 데모 앱까지 한 번에. logs/ 에 기록
	@$(MAKE) log T="_deploy-all AUTO_APPROVE=1" N=deploy

_deploy-all: setup
	@echo "${BLUE}=== 시작 $$(date '+%Y-%m-%d %H:%M:%S') ===${NC}"
	@$(MAKE) deploy
	@$(MAKE) status
	@$(MAKE) cluster-version
	@$(MAKE) addons
	@$(MAKE) insights
	@$(MAKE) test-app
	@echo "${BLUE}=== 완료 $$(date '+%Y-%m-%d %H:%M:%S') ===${NC}"
	@echo "${YELLOW}다음: tfvars 의 kubernetes_version 을 1.36 으로 바꾸고 make upgrade${NC}"

upgrade: session ## tfvars 변경 후 업그레이드. 모니터를 돌리며 logs/ 에 기록
	@$(MAKE) log T="_upgrade AUTO_APPROVE=1" N=upgrade MONITOR=1

_upgrade:
	@echo "${BLUE}=== 업그레이드 시작 $$(date '+%Y-%m-%d %H:%M:%S') ===${NC}"
	@$(MAKE) deploy
	@$(MAKE) cluster-version
	@$(MAKE) addons
	@$(MAKE) insights
	@echo "${BLUE}=== 업그레이드 완료 $$(date '+%Y-%m-%d %H:%M:%S') ===${NC}"

kubeconfig: ## kubectl 설정 업데이트
	@echo "${BLUE}kubectl 설정을 업데이트합니다...${NC}"
	@CLUSTER_NAME=$$(cd terraform && terraform output -raw cluster_name 2>/dev/null || echo "$(CLUSTER_NAME)"); \
	AWS_REGION=$$(cd terraform && terraform output -raw cluster_region 2>/dev/null || echo "$(AWS_REGION)"); \
	aws eks update-kubeconfig --region $$AWS_REGION --name $$CLUSTER_NAME --alias $$CLUSTER_NAME
	@echo "${GREEN}✓ kubectl 컨텍스트: $$(kubectl config current-context)${NC}"
	@command -v kubectx >/dev/null 2>&1 && kubectx | sed 's|^|  |' || true

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

test-app: ## 데모 앱 배포 (ClusterIP)
	@kubectl apply -f k8s-manifests/demo-app.yaml
	@kubectl rollout status deployment/demo-app --timeout=180s
	@$(MAKE) app-status

app-status: ## 데모 앱의 파드가 어느 노드에서 도는지 확인
	@kubectl get pods -l app=demo-app -o wide
	@kubectl get pdb demo-app 2>/dev/null || true

app-open: ## 데모 앱을 로컬 8080 포트로 연결. 끊기면 다시 연결한다
	@echo "${BLUE}http://localhost:8080 에서 확인하세요. 종료는 Ctrl+C${NC}"
	@# port-forward 는 특정 파드에 붙으므로 노드 교체로 파드가 죽으면 종료된다.
	@LOG=$(RUN_DIR)/app-open-$$(date '+%Y%m%d-%H%M%S').log; \
	mkdir -p $(RUN_DIR); \
	while :; do \
		kubectl port-forward svc/demo-app 8080:80 2>&1 \
			| while IFS= read -r l; do \
				printf '[%s] %s\n' "$$(date '+%H:%M:%S')" "$$l" | tee -a $$LOG; \
			done; \
		printf '[%s] 연결이 끊겼습니다. 2초 후 재연결합니다\n' "$$(date '+%H:%M:%S')" | tee -a $$LOG; \
		sleep 2; \
	done

probe: ## Service 의 Ready 엔드포인트 수를 1초마다 기록 (Ctrl+C 로 종료)
	@mkdir -p $(RUN_DIR)
	@LOG=$(RUN_DIR)/probe-$$(date '+%Y%m%d-%H%M%S').log; \
	echo "${BLUE}엔드포인트를 감시합니다. 종료는 Ctrl+C -> $$LOG${NC}"; \
	./scripts/probe.sh 2>&1 | while IFS= read -r l; do printf '%s\n' "$$l" | tee -a $$LOG; done

monitor: ## 클러스터·노드·애드온·파드 상태를 주기적으로 출력 (Ctrl+C 로 종료)
	@CN=$$(cd terraform && terraform output -raw cluster_name 2>/dev/null || echo "$(CLUSTER_NAME)"); \
	CLUSTER=$$CN INTERVAL=$(INTERVAL) ./scripts/monitor.sh

app-watch: ## 롤백 중 파드 상태를 실시간 관찰. 화면과 logs/ 에 같이 남는다
	@mkdir -p $(RUN_DIR)
	@LOG=$(RUN_DIR)/app-watch-$$(date '+%Y%m%d-%H%M%S').log; \
	echo "${BLUE}파드 상태를 관찰합니다. 종료는 Ctrl+C -> $$LOG${NC}"; \
	while :; do \
		kubectl get pods -l app=demo-app -o wide --watch 2>&1 \
			| while IFS= read -r l; do \
				printf '[%s] %s\n' "$$(date '+%H:%M:%S')" "$$l" | tee -a $$LOG; \
			done; \
		printf '[%s] watch 가 끊겼습니다. 다시 붙습니다\n' "$$(date '+%H:%M:%S')" | tee -a $$LOG; \
		sleep 1; \
	done

clean-test-app: ## 데모 앱 삭제
	@kubectl delete -f k8s-manifests/demo-app.yaml --ignore-not-found

destroy: session ## 모든 리소스 삭제. logs/ 에 기록
	@$(MAKE) log T="_destroy" N=destroy

clean-eni: ## VPC 에 남은 미사용 ENI 정리 (destroy 가 DependencyViolation 으로 막힐 때)
	@# terraform output 은 state 가 비면 경고 문구를 내보내므로 형식으로 판정한다.
	@VPC=$$(cd terraform && terraform output -raw vpc_id 2>/dev/null); \
	case "$$VPC" in vpc-*) ;; *) VPC="" ;; esac; \
	if [ -z "$$VPC" ]; then \
		VPC=$$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=$(CLUSTER_NAME)-vpc \
			--query 'Vpcs[0].VpcId' --output text 2>/dev/null); \
		case "$$VPC" in vpc-*) ;; *) VPC="" ;; esac; \
	fi; \
	[ -n "$$VPC" ] || { echo "${YELLOW}VPC 를 찾지 못해 건너뜁니다${NC}"; exit 0; }; \
	echo "${BLUE}VPC $$VPC 의 미사용 ENI 를 확인합니다${NC}"; \
	IDS=$$(aws ec2 describe-network-interfaces \
		--filters Name=vpc-id,Values=$$VPC Name=status,Values=available \
		--query 'NetworkInterfaces[].NetworkInterfaceId' --output text); \
	if [ -z "$$IDS" ]; then \
		echo "${GREEN}남은 ENI 없음${NC}"; \
	else \
		for E in $$IDS; do \
			echo "${YELLOW}미사용 ENI 삭제: $$E${NC}"; \
			aws ec2 delete-network-interface --network-interface-id $$E || true; \
		done; \
	fi

_destroy:
	@echo "${RED}모든 AWS 리소스를 삭제합니다${NC}"
	@echo "${BLUE}=== 삭제 시작 $$(date '+%Y-%m-%d %H:%M:%S') ===${NC}"
	@# 클러스터가 이미 없으면 kubectl 이 응답을 기다리며 멈추므로 타임아웃을 건다.
	@echo "${BLUE}클러스터가 살아 있으면 LoadBalancer 와 PV 를 먼저 정리합니다${NC}"
	@if kubectl --request-timeout=10s get --raw /version >/dev/null 2>&1; then \
		kubectl --request-timeout=30s delete -f k8s-manifests/demo-app.yaml --ignore-not-found || true; \
		kubectl --request-timeout=30s get services -A -o json 2>/dev/null \
			| jq -r '.items[] | select(.spec.type=="LoadBalancer") | "\(.metadata.namespace) \(.metadata.name)"' \
			| while read -r ns name; do kubectl --request-timeout=30s delete service "$$name" -n "$$ns" || true; done; \
		kubectl --request-timeout=60s delete pv --all || true; \
	else \
		echo "${YELLOW}클러스터에 접속할 수 없어 건너뜁니다${NC}"; \
	fi
	@echo "${BLUE}Terraform 으로 인프라를 삭제합니다${NC}"
	@# 삭제 순서는 의존 관계로 정해지므로 parallelism 을 올려도 EKS 쪽 대기 시간은 줄지 않는다.
	@# VPC CNI 가 노드에 붙인 ENI 는 노드 그룹 삭제 후에 남으므로
	@# 사전이 아니라 실패했을 때 정리하고 재시도한다.
	@cd terraform && terraform destroy --parallelism=30 -auto-approve || { \
		echo "${YELLOW}삭제가 실패했습니다. 남은 ENI 를 정리하고 다시 시도합니다${NC}"; \
		$(MAKE) clean-eni; \
		cd terraform && terraform destroy --parallelism=30 -auto-approve; \
	}
	@echo "${BLUE}kubeconfig 정리${NC}"
	@CN="$(CLUSTER_NAME)"; \
	kubectl config get-contexts -o name 2>/dev/null | grep -F "$$CN" | xargs -r -n1 kubectl config delete-context >/dev/null 2>&1 || true; \
	kubectl config get-clusters 2>/dev/null | grep -F "$$CN" | xargs -r -n1 kubectl config delete-cluster >/dev/null 2>&1 || true
	@echo "${BLUE}=== 삭제 완료 $$(date '+%Y-%m-%d %H:%M:%S') ===${NC}"
	@echo "${YELLOW}KMS 키는 7일 대기 후 삭제됩니다. 그동안 과금이 이어집니다${NC}"

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
	@echo "${YELLOW}검증이 끝나면 make destroy 로 정리하세요${NC}"

versions: ## 사용 가능한 EKS 버전과 지원 상태 확인
	@echo "${BLUE}EKS 클러스터 버전 목록${NC}"
	@aws eks describe-cluster-versions \
		--query 'clusterVersions[].{version:clusterVersion,status:status,eos:endOfStandardSupportDate}' \
		--output table

cluster-version: ## 현재 클러스터와 노드 그룹의 버전 확인
	@CN=$$(cd terraform && terraform output -raw cluster_name 2>/dev/null || echo "$(CLUSTER_NAME)"); \
	echo "${BLUE}컨트롤 플레인${NC}"; \
	aws eks describe-cluster --name $$CN \
		--query 'cluster.{version:version,platform:platformVersion,status:status,upgradePolicy:upgradePolicy.supportType}' --output table; \
	echo "${BLUE}노드 그룹${NC}"; \
	for NG in $$(aws eks list-nodegroups --cluster-name $$CN --query 'nodegroups[]' --output text); do \
		aws eks describe-nodegroup --cluster-name $$CN --nodegroup-name $$NG \
			--query 'nodegroup.{name:nodegroupName,version:version,release:releaseVersion,status:status}' --output table; \
	done; \
	echo "${BLUE}노드의 kubelet 버전${NC}"; \
	kubectl get nodes -o custom-columns='NODE:.metadata.name,KUBELET:.status.nodeInfo.kubeletVersion,AMI:.status.nodeInfo.osImage' 2>/dev/null || true

addons: ## 현재 설치된 애드온 버전 확인
	@CN=$$(cd terraform && terraform output -raw cluster_name 2>/dev/null || echo "$(CLUSTER_NAME)"); \
	for A in $$(aws eks list-addons --cluster-name $$CN --query 'addons[]' --output text); do \
		aws eks describe-addon --cluster-name $$CN --addon-name $$A \
			--query 'addon.{name:addonName,version:addonVersion,status:status}' --output table; \
	done

addons-for: ## 지정 Kubernetes 버전의 애드온 기본 버전을 표시. VERSION 필요
	@test -n "$(VERSION)" || { echo "${RED}VERSION 을 지정하세요. 예: make addons-for VERSION=1.35${NC}"; exit 1; }
	@CN=$$(cd terraform && terraform output -raw cluster_name 2>/dev/null || echo "$(CLUSTER_NAME)"); \
	for A in $$(aws eks list-addons --cluster-name $$CN --query 'addons[]' --output text); do \
		V=$$(aws eks describe-addon-versions --addon-name $$A --kubernetes-version $(VERSION) \
			--query 'addons[0].addonVersions[?compatibilities[?defaultVersion==`true`]].addonVersion|[0]' \
			--output text); \
		printf '  %-22s %s\n' "$$A" "$$V"; \
	done

addon-set: ## 애드온을 지정 Kubernetes 버전의 기본 버전으로 맞춤. VERSION 필요
	@test -n "$(VERSION)" || { echo "${RED}VERSION 을 지정하세요. 예: make addon-set VERSION=1.35${NC}"; exit 1; }
	@CN=$$(cd terraform && terraform output -raw cluster_name 2>/dev/null || echo "$(CLUSTER_NAME)"); \
	for A in $$(aws eks list-addons --cluster-name $$CN --query 'addons[]' --output text); do \
		V=$$(aws eks describe-addon-versions --addon-name $$A --kubernetes-version $(VERSION) \
			--query 'addons[0].addonVersions[?compatibilities[?defaultVersion==`true`]].addonVersion|[0]' \
			--output text); \
		[ -n "$$V" ] && [ "$$V" != "None" ] || { echo "${RED}$$A 의 $(VERSION) 기본 버전을 찾지 못했습니다${NC}"; exit 1; }; \
		CUR=$$(aws eks describe-addon --cluster-name $$CN --addon-name $$A --query 'addon.addonVersion' --output text); \
		if [ "$$CUR" = "$$V" ]; then \
			echo "${BLUE}$$(date '+%H:%M:%S') $$A 은 이미 $$V${NC}"; \
			continue; \
		fi; \
		echo "${BLUE}$$(date '+%H:%M:%S') $$A $$CUR -> $$V${NC}"; \
		aws eks update-addon --cluster-name $$CN --addon-name $$A --addon-version $$V \
			--resolve-conflicts OVERWRITE --query 'update.[id,status]' --output text || exit 1; \
		aws eks wait addon-active --cluster-name $$CN --addon-name $$A || exit 1; \
	done
	@$(MAKE) addons

rollback-try-apply: session ## apply 한 번으로 롤백이 되는지 확인한다. 거부되는 것을 기록하는 용도
	@$(MAKE) log T="_rollback-try-apply AUTO_APPROVE=$(AUTO_APPROVE)" N=rollback-try-apply

_rollback-try-apply:
	@echo "${YELLOW}tfvars 를 이전 버전으로 바꾼 상태에서 apply 를 시도합니다${NC}"
	@echo "${YELLOW}Terraform 은 컨트롤 플레인부터 내리므로 kubelet skew 로 거부될 것으로 예상됩니다${NC}"
	@if [ "$(AUTO_APPROVE)" = "1" ]; then \
		echo "${BLUE}확인 없이 진행합니다 (AUTO_APPROVE=1)${NC}"; \
	else \
		printf "${YELLOW}계속하려면 yes 를 입력하세요: ${NC}"; \
		read ans; [ "$$ans" = "yes" ] || { echo "${RED}중단했습니다${NC}"; exit 1; }; \
	fi
	@cd terraform && terraform apply -auto-approve; RC=$$?; \
	if [ $$RC -eq 0 ]; then \
		echo "${YELLOW}apply 가 성공했습니다. 예상과 다르므로 결과를 확인하세요${NC}"; \
	else \
		echo "${BLUE}apply 가 거부됐습니다 (exit=$$RC). 문서 순서대로 rollback-a 를 실행하세요${NC}"; \
	fi

insights: ## 업그레이드·롤백 인사이트 확인 (애드온 호환성 검사 포함)
	@CN=$$(cd terraform && terraform output -raw cluster_name 2>/dev/null || echo "$(CLUSTER_NAME)"); \
	echo "${BLUE}UPGRADE_INSIGHTS (업그레이드 전 확인)${NC}"; \
	aws eks list-insights --cluster-name $$CN \
		--filter '{"categories": ["UPGRADE_READINESS"]}' \
		--query 'insights[].{name:name,status:insightStatus.status,reason:insightStatus.reason}' \
		--output table; \
	echo "${BLUE}ROLLBACK_READINESS (업그레이드 후 7일간만 표시)${NC}"; \
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
		UPD=$$(aws eks update-nodegroup-version --cluster-name $$CN --nodegroup-name $$NG \
			--kubernetes-version $(VERSION) --query 'update.id' --output text); \
		echo "update id: $$UPD"; \
		while :; do \
			ST=$$(aws eks describe-update --name $$CN --nodegroup-name $$NG --update-id $$UPD \
				--query 'update.status' --output text 2>/dev/null); \
			[ -n "$$ST" ] || { echo "${RED}상태를 조회하지 못했습니다. 중단합니다${NC}"; exit 1; }; \
			echo "  $$(date '+%H:%M:%S') $$ST"; \
			case $$ST in \
				InProgress) sleep 30; continue ;; \
				Successful) break ;; \
				*) echo "${RED}노드 그룹 업데이트가 $$ST 입니다${NC}"; \
				   aws eks describe-update --name $$CN --nodegroup-name $$NG --update-id $$UPD \
				     --query 'update.errors' --output table; exit 1 ;; \
			esac; \
		done; \
	done
	@$(MAKE) wait-nodegroup
	@echo "${BLUE}=== 노드 그룹 롤백 종료 $$(date '+%Y-%m-%d %H:%M:%S') ===${NC}"

rollback-cluster: ## 컨트롤 플레인을 이전 버전으로 롤백 (VERSION=1.35 필요)
	@test -n "$(VERSION)" || { echo "${RED}VERSION 을 지정하세요. 예: make rollback-cluster VERSION=1.35${NC}"; exit 1; }
	@echo "${BLUE}컨트롤 플레인을 $(VERSION) 으로 롤백합니다${NC}"
	@echo "${YELLOW}노드 그룹을 먼저 롤백했는지 확인하세요${NC}"
	@if [ "$(AUTO_APPROVE)" = "1" ]; then \
		echo "${BLUE}확인 없이 진행합니다 (AUTO_APPROVE=1)${NC}"; \
	else \
		printf "${YELLOW}계속하려면 yes 를 입력하세요: ${NC}"; \
		read ans; [ "$$ans" = "yes" ] || { echo "${RED}중단했습니다${NC}"; exit 1; }; \
	fi
	@echo "${BLUE}=== 컨트롤 플레인 롤백 시작 $$(date '+%Y-%m-%d %H:%M:%S') ===${NC}"
	@CN=$$(cd terraform && terraform output -raw cluster_name 2>/dev/null || echo "$(CLUSTER_NAME)"); \
	OUT=$$(aws eks update-cluster-version --name $$CN --kubernetes-version $(VERSION) --output json) || \
		{ echo "${RED}롤백 요청이 실패했습니다${NC}"; exit 1; }; \
	echo "$$OUT" | jq -r '.update | "id: \(.id)\ntype: \(.type)\nstatus: \(.status)"'; \
	UPD=$$(echo "$$OUT" | jq -r '.update.id'); \
	[ -n "$$UPD" ] && [ "$$UPD" != "null" ] || { echo "${RED}update id 를 얻지 못했습니다${NC}"; exit 1; }; \
	while :; do \
		ST=$$(aws eks describe-update --name $$CN --update-id $$UPD --query 'update.status' --output text 2>/dev/null); \
		[ -n "$$ST" ] || { echo "${RED}상태를 조회하지 못했습니다. 중단합니다${NC}"; exit 1; }; \
		echo "  $$(date '+%H:%M:%S') $$ST"; \
		case $$ST in \
			InProgress) sleep 30; continue ;; \
			Successful) break ;; \
			*) echo "${RED}컨트롤 플레인 롤백이 $$ST 입니다${NC}"; \
			   aws eks describe-update --name $$CN --update-id $$UPD --query 'update.errors' --output table; \
			   exit 1 ;; \
		esac; \
	done
	@echo "${BLUE}=== 컨트롤 플레인 롤백 종료 $$(date '+%Y-%m-%d %H:%M:%S') ===${NC}"
	@echo "${YELLOW}위 type 이 VersionRollback 이면 롤백으로 처리된 것입니다${NC}"

wait-nodegroup: ## 노드 그룹이 ACTIVE 가 될 때까지 대기
	@CN=$$(cd terraform && terraform output -raw cluster_name 2>/dev/null || echo "$(CLUSTER_NAME)"); \
	for NG in $$(aws eks list-nodegroups --cluster-name $$CN --query 'nodegroups[]' --output text); do \
		while :; do \
			ST=$$(aws eks describe-nodegroup --cluster-name $$CN --nodegroup-name $$NG \
				--query 'nodegroup.status' --output text 2>/dev/null); \
			[ -n "$$ST" ] || { echo "${RED}상태를 조회하지 못했습니다. 중단합니다${NC}"; exit 1; }; \
			echo "  $$(date '+%H:%M:%S') $$NG $$ST"; \
			case $$ST in \
				UPDATING|CREATING) sleep 30; continue ;; \
				ACTIVE) break ;; \
				*) echo "${RED}노드 그룹이 $$ST 입니다. 중단합니다${NC}"; exit 1 ;; \
			esac; \
		done; \
	done

rollback-rest: session ## 중단된 롤백의 컨트롤 플레인부터 이어서 실행. VERSION 필요
	@test -n "$(VERSION)" || { echo "${RED}VERSION 을 지정하세요. 예: make rollback-rest VERSION=1.35${NC}"; exit 1; }
	@$(MAKE) log T="_rollback-rest VERSION=$(VERSION) AUTO_APPROVE=1" N=rollback-rest MONITOR=1

_rollback-rest:
	@$(MAKE) wait-nodegroup
	@$(MAKE) insights
	@$(MAKE) addon-set VERSION=$(VERSION)
	@$(MAKE) rollback-cluster VERSION=$(VERSION)
	@$(MAKE) cluster-version
	@$(MAKE) addons
	@$(MAKE) updates
	@$(MAKE) drift

rollback-a: session ## 패턴 A 롤백. 노드 그룹 -> 애드온 -> 컨트롤 플레인. VERSION 필요
	@test -n "$(VERSION)" || { echo "${RED}VERSION 을 지정하세요. 예: make rollback-a VERSION=1.35${NC}"; exit 1; }
	@$(MAKE) log T="_rollback-a VERSION=$(VERSION) AUTO_APPROVE=1" N=rollback-a MONITOR=1

_rollback-a:
	@$(MAKE) insights
	@$(MAKE) rollback-nodegroup VERSION=$(VERSION)
	@$(MAKE) addon-set VERSION=$(VERSION)
	@$(MAKE) insights
	@$(MAKE) rollback-cluster VERSION=$(VERSION)
	@$(MAKE) cluster-version
	@$(MAKE) addons
	@$(MAKE) updates
	@$(MAKE) drift

rollback-b: session ## 패턴 B 롤백. 애드온 -> 컨트롤 플레인. VERSION 필요
	@test -n "$(VERSION)" || { echo "${RED}VERSION 을 지정하세요. 예: make rollback-b VERSION=1.35${NC}"; exit 1; }
	@$(MAKE) log T="_rollback-b VERSION=$(VERSION) AUTO_APPROVE=1" N=rollback-b MONITOR=1

_rollback-b:
	@$(MAKE) insights
	@$(MAKE) addon-set VERSION=$(VERSION)
	@$(MAKE) insights
	@$(MAKE) rollback-cluster VERSION=$(VERSION)
	@$(MAKE) cluster-version
	@$(MAKE) addons
	@$(MAKE) updates
	@$(MAKE) drift

updates: ## 클러스터와 노드 그룹의 업데이트 이력 확인
	@CN=$$(cd terraform && terraform output -raw cluster_name 2>/dev/null || echo "$(CLUSTER_NAME)"); \
	echo "${BLUE}클러스터 업데이트 이력${NC}"; \
	for ID in $$(aws eks list-updates --name $$CN --query 'updateIds[]' --output text); do \
		aws eks describe-update --name $$CN --update-id $$ID \
			--query 'update.{type:type,status:status,created:createdAt}' --output text; \
	done | sort -k3; \
	echo "${BLUE}노드 그룹 업데이트 이력${NC}"; \
	for NG in $$(aws eks list-nodegroups --cluster-name $$CN --query 'nodegroups[]' --output text); do \
		for ID in $$(aws eks list-updates --name $$CN --nodegroup-name $$NG --query 'updateIds[]' --output text); do \
			aws eks describe-update --name $$CN --nodegroup-name $$NG --update-id $$ID \
				--query 'update.{type:type,status:status,created:createdAt}' --output text; \
		done | sort -k3; \
	done

drift: ## 롤백 후 Terraform 과 실제 상태의 차이 확인
	@echo "${BLUE}terraform plan 으로 drift 를 확인합니다${NC}"
	@# -detailed-exitcode: 0 차이 없음, 1 에러, 2 차이 있음
	@cd terraform && terraform plan -detailed-exitcode; RC=$$?; \
	case $$RC in \
		0) echo "${GREEN}코드와 실제 상태가 일치합니다${NC}" ;; \
		2) echo "${YELLOW}차이가 있습니다. kubernetes_version 을 실제 버전에 맞추세요${NC}" ;; \
		*) echo "${RED}plan 이 실패했습니다 (exit=$$RC)${NC}"; exit $$RC ;; \
	esac

# --- Argo CD 이관 (gitops/) ---
# 브랜치 A 는 Helm 자체 운영, 브랜치 B 는 Capability 로 이관한 상태다. 로그 이름에 브랜치를 붙인다.
GITOPS_DIR = gitops
BRANCH = $(shell git rev-parse --abbrev-ref HEAD | tr '/' '-')

gitops-init: ## gitops/ 루트 초기화
	@cd $(GITOPS_DIR) && terraform init

gitops-plan: session ## 현재 브랜치의 gitops/ 실행 계획. logs/ 에 기록
	@$(MAKE) log T="_gitops-plan" N=gitops-plan-$(BRANCH)

_gitops-plan:
	@echo "${BLUE}브랜치: $(BRANCH)${NC}"
	@cd $(GITOPS_DIR) && terraform plan

gitops-apply: session ## 현재 브랜치의 gitops/ 적용. logs/ 에 기록. AUTO_APPROVE=1 로 확인 생략
	@$(MAKE) log T="_gitops-apply AUTO_APPROVE=$(AUTO_APPROVE)" N=gitops-apply-$(BRANCH)

_gitops-apply:
	@echo "${BLUE}=== gitops apply 시작 $$(date '+%Y-%m-%d %H:%M:%S') 브랜치 $(BRANCH) ===${NC}"
	@cd $(GITOPS_DIR) && terraform plan -out=tfplan
	@if [ "$(AUTO_APPROVE)" != "1" ]; then \
		printf "${YELLOW}위 계획대로 적용합니다. 계속하려면 yes 를 입력하세요: ${NC}"; \
		read ans; [ "$$ans" = "yes" ] || { echo "${RED}중단했습니다${NC}"; exit 1; }; \
	fi
	@cd $(GITOPS_DIR) && terraform apply tfplan
	@rm -f $(GITOPS_DIR)/tfplan
	@$(MAKE) --no-print-directory argocd-apps
	@echo "${BLUE}=== gitops apply 완료 $$(date '+%Y-%m-%d %H:%M:%S') ===${NC}"

gitops-destroy: session ## gitops/ 리소스 삭제. make destroy 전에 실행. logs/ 에 기록
	@$(MAKE) log T="_gitops-destroy" N=gitops-destroy

_gitops-destroy:
	@cd $(GITOPS_DIR) && terraform destroy -auto-approve

argocd-ui: ## 자체 운영 Argo CD UI 를 https://localhost:8080 으로 연결 (브랜치 A)
	@kubectl -n gitops port-forward svc/argo-cd-argocd-server 8080:443

argocd-password: ## 자체 운영 Argo CD 로컬 계정의 비밀번호 표시 (브랜치 A)
	@cd $(GITOPS_DIR) && terraform output -raw argocd_password; echo

argocd-apps: ## Application 의 동기화·헬스 상태 확인
	@kubectl -n gitops get applications.argoproj.io \
		-o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision,DESTINATION:.spec.destination

clean: ## 임시 파일 정리 (lock 파일은 재현성을 위해 유지)
	@echo "${BLUE}임시 파일을 정리합니다...${NC}"
	@rm -f terraform/terraform.tfstate.backup
	@rm -f terraform/tfplan
	@echo "${GREEN}✓ 임시 파일이 정리되었습니다${NC}"
	@echo "${YELLOW}참고: .terraform.lock.hcl 은 provider 버전 고정용이라 삭제하지 않습니다${NC}"


# 기본 타겟
.DEFAULT_GOAL := help