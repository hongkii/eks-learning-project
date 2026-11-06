# Migrate self-managed Argo CD to the EKS Capability for Argo CD

Date: 2026-11-06
Status: approved design, implementation plan not written yet

## Goal

Build a self-managed Argo CD on this cluster, migrate it to the Amazon EKS Capability for Argo CD,
and record every step. The records are the only source for a blog post, so every claim in the post
must come from a run in this repository or from the AWS documentation.

Spec baseline is the documentation as of November 2026, after Argo CD Notifications support
(What's New, 2026-11-03).

## Non-goals

- ALB, ACM, Route 53, AWS Load Balancer Controller and Dex SAML are not built. The UI of the
  self-managed Argo CD is reached with `kubectl port-forward`. The post states that these parts were
  not built and describes them from the documentation only.
- Multi-cluster (hub and spoke) is out of scope.

## Prerequisites (manual, outside Terraform)

| Item | Detail |
| --- | --- |
| IAM Identity Center | Account instance in this account, one user and one group. The capability supports account instances, and the instance cannot be changed after the capability is created. |
| GitHub | New private repository for the application manifests, fine-grained PAT limited to that repository with Contents read-only. |
| Slack | App with a bot token (`chat:write`) and a channel the bot is invited to. |
| Secret values | The user stores the PAT and the Slack token in Secrets Manager. Terraform creates the secret containers only. |
| AWS session | MFA session through `make session`. |

## Architecture

Two Terraform root modules. The cluster root and the root that configures the helm and kubernetes
providers from that cluster are kept apart, so one apply never both creates the cluster and needs it.

| Root | Owns | Providers |
| --- | --- | --- |
| `terraform/` (existing) | VPC, EKS, node group, add-ons | aws, tls |
| `gitops/` (new) | Everything Argo CD: Helm release, capability, IAM, SQS, EventBridge, Secrets Manager containers, Kubernetes objects | aws, helm, kubernetes, alekc/kubectl |

`gitops/` reads the cluster with `data "aws_eks_cluster"` and authenticates with `aws eks get-token`.
`kubectl_manifest` (alekc/kubectl) is used for Argo CD custom resources because it plans without the
CRDs being present.

### Changes to `terraform/`

- `aws_eks_cluster.main`: add `access_config` with `authentication_mode = "API_AND_CONFIG_MAP"` and
  `bootstrap_cluster_creator_admin_permissions = true`. The EKS API default is `CONFIG_MAP`, and access
  entries need `API` or `API_AND_CONFIG_MAP`. The capability creates an access entry for its role.
- `terraform.tfvars` during this work: `instance_types = ["t3.medium"]`, `capacity_type = "ON_DEMAND"`.
  t3.small allows 11 pods per node, and system pods plus a self-managed Argo CD already use most of 22.

## Migration stages

`gitops/` takes `var.stage`. Each stage is one `terraform apply`. Rollback is an apply of an earlier
stage.

| Stage | Official step | State |
| --- | --- | --- |
| `self-managed` | before | Helm Argo CD runs and syncs both Applications; notifications reach SQS and Slack |
| `scaled-down` | 2 | Helm values set every Argo CD controller to 0 replicas |
| `capability` | 3 to 9 | Capability created and Argo CD objects moved to the capability |
| `decommissioned` | 10 | Helm release and IRSA role removed |

### Resources per stage

| Resource | self-managed | scaled-down | capability | decommissioned |
| --- | --- | --- | --- | --- |
| `helm_release` argo-cd (`argocd` namespace) | running | 0 replicas | 0 replicas, `argocd-cm` and notifications ConfigMap no longer rendered | removed |
| IRSA role for the notifications controller | yes | yes | yes | removed |
| SQS queue (SSE-SQS), EventBridge bus, rule, CloudWatch Logs target | yes | yes | yes | yes |
| Secrets Manager containers (PAT, Slack token) | yes | yes | yes | yes |
| Repository Secret | PAT value | PAT value | Secrets Manager reference | Secrets Manager reference |
| `argocd-notifications-secret` | token value | token value | Secrets Manager ARN | Secrets Manager ARN |
| Capability role and policy | - | - | yes | yes |
| `aws_eks_capability` (`type = "ARGOCD"`, `delete_propagation_policy = "RETAIN"`) | - | - | yes | yes |
| Access policy association for the capability role | - | - | yes | yes |
| Cluster Secret named `in-cluster` with the cluster ARN | - | - | yes | yes |
| `argocd-cm` | Helm | Helm | Terraform, label `app.kubernetes.io/part-of: argocd` | Terraform |
| `argocd-notifications-cm` | Helm | Helm | Terraform, label `eks.amazonaws.com/managed-notifications: "enabled"` | Terraform |
| Capability log delivery (application and notification logs) | - | - | yes | yes |
| Applications | `server: https://kubernetes.default.svc` | same | `name: in-cluster` | same |

## Self-managed Argo CD (stage `self-managed`)

- Chart `argo-cd`, latest version at implementation time, pinned. Dex disabled, local admin.
- `argocd-cm`: `kustomize.buildOptions: --load-restrictor LoadRestrictionsNone`, one
  `resource.customizations.ignoreDifferences` entry, `ui.bannercontent`.
- Notifications: services `awssqs` (IRSA) and `slack`, own triggers and templates,
  `TZ=Asia/Tokyo` on the controller, and one template that prints the same time twice:
  `{{ (call .time.Parse .app.status.operationState.finishedAt).Local.Format "2006-01-02 15:04 MST" }}`
  and `{{ dateInZone "2006-01-02 15:04 MST" (call .time.Parse .app.status.operationState.finishedAt) "Asia/Tokyo" }}`.
- Applications from the private repository, both with `resources-finalizer.argocd.argoproj.io`:
  - `app-auto`: automated sync with prune.
  - `app-manual`: manual sync, and its overlay loads a file outside the kustomization root through
    `configMapGenerator`, so it needs `--load-restrictor LoadRestrictionsNone`.

## Capability (stage `capability`)

- Capability role trusted by `capabilities.eks.amazonaws.com` with `sts:AssumeRole` and
  `sts:TagSession`. Permissions: `sqs:GetQueueUrl`, `sqs:SendMessage`, `events:PutEvents`, and
  `secretsmanager:GetSecretValue` on the two secrets.
- `configuration.argo_cd`: `aws_idc` (account instance), namespace `argocd`, `rbac_role_mapping` with
  the group as `ADMIN`.
- The automatic access entry grants no rights to deploy applications. `AmazonEKSEditPolicy` is
  associated to the application namespace; the namespace is created by Terraform.
- Notifications add the `eventbridge` service sending to the custom bus.

## Secret handling

Secret values never appear in Terraform state, plan output, or the assistant's context.
Candidate mechanism: ephemeral `aws_secretsmanager_secret_version` feeding write-only Secret data.
The `aws-secrets-manager` skill is read before implementation and its rules win over this candidate.

## Verification items

Each item is captured under `logs/<date>/` with the commands and outputs.

1. Error shown for `app-manual` after migration, because `--load-restrictor` is dropped.
2. Notification time from `.Local.Format` and from `dateInZone "Asia/Tokyo"` on the capability.
3. Argo CD version of the capability compared with the chart, and the CRDs after the capability is
   created over CRDs installed by Helm.
4. Takeover of deployed resources: tracking annotation change (`app:` to `argocd_app:`), sync status,
   shared resource warnings, and whether prune deletes anything.
5. Moving `argocd-cm` and `argocd-notifications-cm` from Helm to Terraform in the shared `argocd`
   namespace, and what the capability reads at each point.
6. A Terraform plan that replaces an Application, with the finalizer present (plan only unless
   isolated with a throwaway Application).
7. `awssqs` and `eventbridge` delivery with the capability role, Slack token resolved from
   Secrets Manager.
8. Rollback from `capability` to `self-managed`.
9. Cost of each stage in ap-northeast-1.

## Cost (ap-northeast-1, approximate, to be rechecked against the price list before the run)

EKS control plane, one NAT Gateway, two t3.medium on-demand nodes, capability $0.037486 per hour and
$0.001853 per Application hour (price list published 2026-10-27), two Secrets Manager secrets.

## Teardown

`decommissioned` then `terraform destroy` in `gitops/` then `make destroy`. Applications are deleted
before the capability so the finalizer is processed while a controller still runs.

## Open risks

- The capability's Argo CD version is not documented. It may be lower than the chart.
- Whether the capability runtime ships tzdata is not documented. `dateInZone` falls back to UTC
  without an error.
- Behaviour when the capability installs CRDs over Helm-installed CRDs is not documented.
- An account instance of IAM Identity Center may be blocked by the organization.

## References

- https://docs.aws.amazon.com/eks/latest/userguide/argocd-comparison.html
- https://docs.aws.amazon.com/eks/latest/userguide/create-argocd-capability.html
- https://docs.aws.amazon.com/eks/latest/userguide/argocd-configure-settings.html
- https://docs.aws.amazon.com/eks/latest/userguide/argocd-notifications.html
- https://docs.aws.amazon.com/eks/latest/userguide/argocd-register-clusters.html
- https://docs.aws.amazon.com/eks/latest/userguide/capabilities-security.html
- https://docs.aws.amazon.com/eks/latest/userguide/capability-role.html
- https://docs.aws.amazon.com/eks/latest/userguide/setting-up-access-entries.html
- https://aws.amazon.com/about-aws/whats-new/2026/11/amazon-eks-argo-cd-notifications/
