# EKS Terraform Study Project

An EKS cluster built with Terraform for learning Kubernetes. Currently used to verify **EKS version rollback**.

## Architecture

```
VPC (10.0.0.0/16)
├── Public Subnet  x2   IGW, NAT Gateway
└── Private Subnet x2   EKS control plane ENIs, worker nodes
```

| Item | Value |
| --- | --- |
| Kubernetes | 1.34 (standard support) |
| AMI | AL2023_x86_64_STANDARD |
| Instances | t3.small SPOT x2 |
| Add-ons | vpc-cni, kube-proxy, coredns, aws-ebs-csi-driver |
| Encryption | KMS (etcd secrets), EBS gp3 |
| Metadata | IMDSv2 required (`http_tokens = required`) |

A single NAT Gateway is created by default. Set `single_nat_gateway = false` for per-AZ fault isolation.

## Prerequisites

```bash
terraform version   # >= 1.13
aws --version       # >= 2.12.3
kubectl version --client

export AWS_PROFILE=cm-yim.hongki
aws sts get-caller-identity
```

## Deploy

```bash
make setup     # terraform init
make plan      # review the execution plan
make deploy    # deploy. Shows the plan and asks for a yes confirmation
make status    # check nodes and system pods
```

Settings live in `terraform/terraform.tfvars`, which is gitignored.

## Demo App

Displays which node each pod runs on. Useful for observing behavior during node replacement or rollback.

```bash
make test-app     # deploy (ClusterIP, no extra charge)
make app-status   # check pods and nodes
make app-open     # forward to http://localhost:8080
make app-watch    # watch pod status during a rollback
```

## Version Rollback Verification

EKS allows rolling back to the previous minor version within 7 days of an in-place upgrade.
A cluster cannot be rolled back to the version it was created at, so create at 1.34, upgrade to 1.35, then roll back.

<https://docs.aws.amazon.com/eks/latest/userguide/rollback-cluster.html>

```bash
make versions                            # check support status per version
# change kubernetes_version to 1.35 in terraform.tfvars
make deploy                              # 1.34 to 1.35
make insights                            # check ROLLBACK_READINESS
make rollback-nodegroup VERSION=1.34     # node group first
make rollback-cluster VERSION=1.34       # control plane
make updates                             # confirm the type is VersionRollback
make drift                               # check the difference against Terraform
```

Managed node groups are not rolled back automatically. They must be rolled back before the control plane.
Add-ons are not rolled back either, so they need to be handled separately.

The Terraform AWS Provider does not support rollback yet. After rolling back with the CLI,
align `kubernetes_version` in the code with the actual version.

- <https://github.com/hashicorp/terraform-provider-aws/issues/48751>

## Destroy

```bash
make destroy
```

The target removes LoadBalancer services and PersistentVolumes first, then runs terraform destroy.
Both leave AWS resources behind if terraform destroy runs on its own.

The KMS key is not deleted immediately. It enters a 7 day pending deletion window, which is the
minimum AWS allows, and is billed until it is gone.

## Cost

```bash
make cost-note
```

EKS control plane $0.10/h, NAT Gateway $0.045/h, t3.small SPOT x2 about $0.014/h.
Roughly $0.16/h in total. Destroy the cluster once verification is done.

## Layout

| File | Contents |
| --- | --- |
| `terraform/vpc.tf` | VPC, subnets, NAT Gateway, routing |
| `terraform/eks.tf` | Cluster, KMS, CloudWatch logs, add-ons |
| `terraform/node-group.tf` | Launch template, managed node group |
| `terraform/iam.tf` | Cluster and node roles, IRSA, OIDC provider |
| `terraform/security-groups.tf` | Cluster, node and ALB security groups |
| `k8s-manifests/demo-app.yaml` | Demo app (Deployment, Service, PDB) |
| `k8s-manifests/` | EBS StorageClass and PVC examples |

## References

- [EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [EKS Best Practices Guide](https://docs.aws.amazon.com/eks/latest/best-practices/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

---

Built for learning. A production setup needs additional security, monitoring and backup.
