# EKS Terraform 스터디 프로젝트

이 프로젝트는 Kubernetes 학습을 위한 AWS EKS 클러스터를 Terraform으로 구축하는 예제입니다. AWS EKS 공식 문서와 베스트 프랙티스를 기반으로 작성되었으며, 학습 목적으로 최적화되어 있습니다.

## 목차

- [아키텍처 개요](#아키텍처-개요)
- [사전 요구사항](#사전-요구사항)
- [빠른 시작](#빠른-시작)
- [파일 구조](#파일-구조)
- [상세 설명](#상세-설명)
- [배포 후 확인](#배포-후-확인)
- [클린업 (리소스 삭제)](#클린업-리소스-삭제)
- [비용 관리](#비용-관리)
- [문제 해결](#문제-해결)

## 아키텍처 개요

이 Terraform 구성은 다음과 같은 AWS 리소스를 생성합니다:

```
┌─────────────────────────────────────────────────────────┐
│                        VPC (10.0.0.0/16)                │
├─────────────────────┬───────────────────────────────────┤
│   Public Subnet 1   │         Public Subnet 2          │
│   (10.0.0.0/24)     │         (10.0.1.0/24)           │
│  - Internet Gateway │       - Internet Gateway         │
│  - NAT Gateway 1    │       - NAT Gateway 2            │
├─────────────────────┼───────────────────────────────────┤
│  Private Subnet 1   │        Private Subnet 2          │
│   (10.0.10.0/24)    │        (10.0.11.0/24)           │
│  - EKS Worker Nodes │      - EKS Worker Nodes          │
│  - EKS Control Plane│      - EKS Control Plane         │
└─────────────────────┴───────────────────────────────────┘
```

### 주요 구성 요소

- **VPC**: Multi-AZ 고가용성 네트워크
- **EKS 1.33**: 사이드카 컨테이너 stable 지원, Dynamic Resource Allocation
- **Amazon Linux 2023**: AL2 지원 종료로 AL2023 AMI 사용
- **Enhanced CNI**: 네트워크 성능 최적화
- **EBS CSI v2**: 영구 볼륨 관리
- **KMS 암호화**: etcd 및 시크릿 암호화

## 사전 요구사항

**중요**: 배포하기 전에 필수 도구를 설치하세요.

### 빠른 확인

```bash
# 프로젝트 디렉토리로 이동
cd eks-terraform

# 필수 도구 버전 확인
terraform version    # v1.13.0 (프로젝트 지정 버전)
aws --version       # >= 2.12.3 필요
kubectl version --client  # >= 1.32 권장
aws sts get-caller-identity  # AWS 계정 확인
```

**특징**: 이 프로젝트는 `.terraform-version` 파일로 `tfenv`와 호환됩니다.

필수 도구:

- Terraform >= 1.9
- AWS CLI >= 2.12.3
- kubectl >= 1.32

## 빠른 시작

### 방법 A: Makefile 사용 (권장)

```bash
git clone https://github.com/your-username/eks-terraform
cd eks-terraform

# 1. 도움말 확인
make help

# 2. 자동 배포 (권장)
make all          # setup + plan + deploy + status 한 번에 실행

# 또는 단계별 실행
make setup        # 초기 설정 및 terraform.tfvars 생성
make plan         # 실행 계획 확인
make deploy       # 클러스터 배포 (10-15분)
make status       # 상태 확인

# 3. 테스트 앱 배포 (선택사항)
make test-app     # nginx 테스트 애플리케이션

# 4. 리소스 삭제
make destroy      # 모든 AWS 리소스 삭제
```

### 방법 B: 수동 Terraform 실행

#### 1. 프로젝트 클론 및 설정

```bash
git clone https://github.com/your-username/eks-terraform
cd eks-terraform

# 변수 파일 생성
cp terraform.tfvars.example terraform.tfvars
```

#### 2. 변수 파일 수정

`terraform.tfvars` 파일을 열어 다음 값들을 수정하세요:

```hcl
# 필수 수정 항목
cluster_name      = "your-study-cluster"    # 원하는 클러스터 이름
ec2_key_pair_name = "your-key-pair-name"    # SSH 키 페어 이름 (선택사항)

# 선택적 수정 항목
aws_region        = "ap-northeast-2"        # 원하는 AWS 리전
environment       = "dev"                   # 환경 구분
```

#### 3. Terraform 실행

```bash
# Terraform 초기화
cd terraform
terraform init

# 실행 계획 확인
terraform plan -var-file=../terraform.tfvars

# 리소스 생성 (약 10-15분 소요)
terraform apply
```

#### 4. kubectl 설정 (수동 방식)

```bash
# kubeconfig 업데이트
aws eks update-kubeconfig --region ap-northeast-2 --name your-study-cluster

# 클러스터 연결 확인
kubectl get nodes
kubectl get pods --all-namespaces
```

> **참고**: Makefile을 사용하면 `make deploy` 명령 시 자동으로 kubectl 설정이 완료됩니다.

## 파일 구조

```
eks-terraform/
├── terraform/               # Terraform 구성 파일들
│   ├── versions.tf          # 프로바이더 및 버전 설정
│   ├── variables.tf         # 입력 변수 정의
│   ├── outputs.tf           # 출력 변수 정의
│   ├── vpc.tf               # VPC 및 네트워킹
│   ├── security-groups.tf   # 보안 그룹
│   ├── iam.tf               # IAM 역할 및 정책
│   ├── eks.tf               # EKS 클러스터
│   ├── node-group.tf        # EKS 노드 그룹
│   ├── .terraform-version   # Terraform 버전 고정
│   └── terraform.tfvars.example  # 변수 예시
├── scripts/                 # 유틸리티 스크립트
│   ├── validate-deployment.sh   # 배포 검증
│   └── cost-calculator.sh       # 비용 계산기
├── terraform.tfvars.example # 변수 예시 파일
├── Makefile                 # 자동화 도구
├── LICENSE                  # MIT 라이선스
└── README.md               # 기본 문서
```

## 상세 설명

### VPC 및 네트워킹 (`vpc.tf`)

- **고가용성**: 2개 가용 영역에 분산 배치
- **보안**: 워커 노드는 프라이빗 서브넷에 배치
- **확장성**: NAT 게이트웨이로 아웃바운드 연결 제공

### 보안 설정 (`security-groups.tf`)

- **최소 권한 원칙**: 필요한 포트만 개방
- **계층적 보안**: 클러스터, 노드, ALB별 보안 그룹 분리
- **SSH 접근**: VPC 내에서만 SSH 허용

### IAM 권한 (`iam.tf`)

- **EKS 클러스터 역할**: 컨트롤 플레인 관리 권한
- **노드 그룹 역할**: 워커 노드 운영 권한
- **OIDC 연동**: 쿠버네티스 서비스 어카운트와 IAM 역할 매핑

### EKS 클러스터 (`eks.tf`)

- **Kubernetes 1.33**: 사이드카 컨테이너, 토폴로지 인식 라우팅
- **AL2023 AMI**: AL2 지원 종료로 마이그레이션
- **Dynamic Resource Allocation**: GPU 등 특수 리소스 스케줄링
- **Enhanced Security**: IMDSv2 강제, KMS 암호화

### 노드 그룹 (`node-group.tf`)

- **AL2023 AMI**: Kubernetes 1.33 지원
- **Dynamic SSH**: 키 페어 없이도 배포 가능
- **IMDSv2 강제**: 메타데이터 보안 강화
- **Launch Template**: 고급 인스턴스 설정 지원

## 배포 후 확인

### 1. 클러스터 상태 확인

```bash
# 클러스터 정보 확인
kubectl cluster-info

# 노드 상태 확인
kubectl get nodes -o wide

# 시스템 파드 확인
kubectl get pods -n kube-system
```

### 2. 샘플 애플리케이션 배포

```bash
# nginx 배포
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=LoadBalancer

# 서비스 확인
kubectl get services
```

### 3. AWS 콘솔에서 확인

- EKS 클러스터: https://console.aws.amazon.com/eks/
- EC2 인스턴스: https://console.aws.amazon.com/ec2/
- VPC: https://console.aws.amazon.com/vpc/

## 클린업 (리소스 삭제)

**중요: 모든 쿠버네티스 리소스를 먼저 삭제해야 합니다!**

### 1. LoadBalancer 서비스 삭제

```bash
# LoadBalancer 타입 서비스 확인
kubectl get services --all-namespaces

# LoadBalancer 서비스 삭제 (ELB 정리용)
kubectl delete service nginx  # 예시
```

### 2. PersistentVolume 정리

```bash
# PV 확인 및 삭제
kubectl get pv
kubectl delete pv --all
```

### 3. Terraform으로 인프라 삭제

```bash
# 리소스 삭제 (약 10-15분 소요)
cd terraform
terraform destroy -var-file=../terraform.tfvars

# 확인 메시지에서 'yes' 입력
```

### 4. 수동 정리 (필요시)

일부 리소스가 남아있을 수 있습니다:

```bash
# ELB 확인 및 삭제
aws elbv2 describe-load-balancers
aws elb describe-load-balancers

# Security Group 확인
aws ec2 describe-security-groups --filters "Name=group-name,Values=*eks*"
```

## 비용 관리

### 비용 절약 팁

1. **스터디 후 즉시 삭제**: `make destroy` 또는 `terraform destroy`
2. **스팟 인스턴스 사용**: `capacity_type = "SPOT"`
3. **더 작은 인스턴스**: `instance_types = ["t3.small"]`
4. **단일 AZ 사용**: NAT Gateway 1개만 사용하여 비용 절반

## 문제 해결

### 자주 발생하는 문제들

#### 1. 키 페어 오류

```
Error: InvalidKeyPair.NotFound
```

**해결**: `ec2_key_pair_name = ""`로 설정하면 SSH 키 없이도 배포 가능

#### 2. 권한 부족

```
Error: AccessDenied
```

**해결**: AWS 계정에 필요한 IAM 권한 확인:

- EKS 클러스터 생성/관리
- EC2 인스턴스 생성/관리
- VPC 생성/관리
- IAM 역할 생성/관리

#### 3. AL2023 AMI 관련 문제

```bash
# 지원되는 AMI 타입 확인
aws eks describe-addon-versions --addon-name vpc-cni --kubernetes-version 1.33

# 노드 그룹 상태 확인
aws eks describe-nodegroup --cluster-name your-cluster-name --nodegroup-name your-nodegroup-name
```

#### 4. kubectl 연결 실패

```bash
# kubeconfig 재설정
aws eks update-kubeconfig --region ap-northeast-2 --name your-cluster-name --debug

# AWS 자격 증명 확인
aws sts get-caller-identity
```

### 로그 및 모니터링

```bash
# EKS 클러스터 로그 확인
aws logs describe-log-groups --log-group-name-prefix /aws/eks/your-cluster-name

# 노드 상태 디버깅
kubectl describe nodes
kubectl get events --all-namespaces --sort-by='.metadata.creationTimestamp'
```

## 학습 리소스

- [AWS EKS 사용자 가이드](https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/)
- [AWS EKS 베스트 프랙티스](https://aws.github.io/aws-eks-best-practices/)
- [Kubernetes 공식 문서](https://kubernetes.io/ko/docs/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [tfenv GitHub](https://github.com/tfutils/tfenv) - Terraform 버전 관리

## 기여 및 피드백

이 프로젝트는 학습 목적으로 만들어졌습니다. 개선사항이나 문제점을 발견하시면 이슈를 등록해 주세요.

---

**주의사항**: 이 구성은 학습 목적으로 설계되었습니다. 운영 환경에서 사용하려면 보안 강화, 모니터링, 백업 전략 등을 추가로 구성해야 합니다.
