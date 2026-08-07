# EKS Terraform 스터디 프로젝트

Kubernetes 학습용 EKS 클러스터를 Terraform으로 구축한다. 현재는 **EKS 버전 롤백 검증**에 사용한다.

## 구성

```
VPC (10.0.0.0/16)
├── Public Subnet  x2   IGW, NAT Gateway
└── Private Subnet x2   EKS 컨트롤 플레인 ENI, 워커 노드
```

| 항목 | 값 |
| --- | --- |
| Kubernetes | 1.34 (standard support) |
| AMI | AL2023_x86_64_STANDARD |
| 인스턴스 | t3.small SPOT x2 |
| 애드온 | vpc-cni, kube-proxy, coredns, aws-ebs-csi-driver |
| 암호화 | KMS (etcd secrets), EBS gp3 |
| 메타데이터 | IMDSv2 필수 (`http_tokens = required`) |

NAT Gateway는 기본 1개다. AZ 장애 격리가 필요하면 `single_nat_gateway = false` 로 바꾼다.

## 사전 요구사항

```bash
terraform version   # >= 1.13
aws --version       # >= 2.12.3
kubectl version --client

export AWS_PROFILE=cm-yim.hongki
aws sts get-caller-identity
```

## 배포

```bash
make setup     # terraform init
make plan      # 실행 계획 확인
make deploy    # 배포. plan 을 보여주고 yes 확인을 받는다
make status    # 노드와 시스템 파드 확인
```

설정은 `terraform/terraform.tfvars` 에서 바꾼다. 이 파일은 gitignore 대상이다.

## 데모 앱

파드가 어느 노드에서 도는지 화면에 표시한다. 노드 교체나 롤백 중 동작을 확인할 때 쓴다.

```bash
make test-app     # 배포 (ClusterIP, 과금 없음)
make app-status   # 파드와 노드 확인
make app-open     # http://localhost:8080 으로 연결
make app-watch    # 롤백 중 파드 상태 실시간 관찰
```

## 버전 롤백 검증

EKS는 in-place 업그레이드 후 7일 이내에 한 단계 이전 마이너 버전으로 되돌릴 수 있다.
생성 당시 버전으로는 되돌릴 수 없으므로 1.34로 만들고 1.35로 올린 뒤 되돌린다.

<https://docs.aws.amazon.com/eks/latest/userguide/rollback-cluster.html>

```bash
make versions                            # 버전별 지원 상태 확인
# terraform.tfvars 의 kubernetes_version 을 1.35 로 변경
make deploy                              # 1.34 → 1.35
make insights                            # ROLLBACK_READINESS 확인
make rollback-nodegroup VERSION=1.34     # 노드 그룹 먼저
make rollback-cluster VERSION=1.34       # 컨트롤 플레인
make updates                             # type 이 VersionRollback 인지 확인
make drift                               # Terraform 과의 차이 확인
```

관리형 노드 그룹은 자동으로 롤백되지 않는다. 컨트롤 플레인보다 먼저 되돌려야 한다.
애드온도 자동으로 되돌아가지 않으므로 별도로 관리한다.

Terraform AWS Provider는 아직 롤백을 지원하지 않는다. CLI로 되돌린 뒤 코드의
`kubernetes_version` 을 실제 버전에 맞춰야 한다.

- <https://github.com/hashicorp/terraform-provider-aws/issues/48751>

## 삭제

```bash
make destroy
```

LoadBalancer 서비스와 PV를 먼저 정리한 뒤 Terraform destroy를 실행한다.

## 비용

```bash
make cost-note
```

EKS 컨트롤 플레인 $0.10/h, NAT Gateway $0.045/h, t3.small SPOT x2 약 $0.014/h.
합계 약 $0.16/h. 검증이 끝나면 반드시 삭제한다.

## 파일 구성

| 파일 | 내용 |
| --- | --- |
| `terraform/vpc.tf` | VPC, 서브넷, NAT Gateway, 라우팅 |
| `terraform/eks.tf` | 클러스터, KMS, CloudWatch 로그, 애드온 |
| `terraform/node-group.tf` | Launch Template, 관리형 노드 그룹 |
| `terraform/iam.tf` | 클러스터·노드 역할, IRSA, OIDC 프로바이더 |
| `terraform/security-groups.tf` | 클러스터·노드·ALB 보안 그룹 |
| `k8s-manifests/demo-app.yaml` | 데모 앱 (Deployment, Service, PDB) |
| `k8s-manifests/` | EBS StorageClass, PVC 예제 |

## 참고

- [EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [EKS Best Practices Guide](https://docs.aws.amazon.com/eks/latest/best-practices/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

---

학습 목적 구성이다. 운영 환경에서는 보안, 모니터링, 백업을 추가로 구성해야 한다.
