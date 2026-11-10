# Migrate self-managed Argo CD to the EKS Capability for Argo CD

Date: 2026-11-06, revised 2026-11-10
Status: approved design, implementation plan in `docs/superpowers/plans/`

## Goal

Build a self-managed Argo CD on this cluster in the shape that is common in production, migrate it
to the Amazon EKS Capability for Argo CD, and record every step. The records are the only source for
a blog post, so every claim in the post must come from a run in this repository or from the AWS
documentation.

Spec baseline is the documentation as of November 2026, after Argo CD Notifications support
(What's New, 2026-11-03).

## Approach: two branches, two applies

| Branch | Content |
| --- | --- |
| `feat/argocd-self-managed` (A) | The state before the migration. Argo CD from the Helm chart, managed by Terraform. |
| `feat/argocd-capability` (B) | A plus the migration commits. |

Deploy A, check it, then check out B and run `terraform apply` once. The diff from A to B is the
migration change a team would review. Rollback is an apply of A.

B keeps the Helm release, scaled to zero, so that one apply follows the official order
(scale down first, then create the capability). Terraform can order the new resources after the Helm
release only while the release is still in the configuration. Removing the release is the last
commit on B (official step 10) and is applied after the checks.

## Non-goals

- ALB, ACM, Route 53 and the AWS Load Balancer Controller are not built. The self-managed UI is
  reached with `kubectl port-forward` on `https://localhost:8080`.
- Multi-cluster (hub and spoke) is out of scope.

## Prerequisites (manual, outside Terraform)

| Item | Detail |
| --- | --- |
| AWS session | Profile `cm-yim.hongki`. Every apply in this repository uses it. |
| IAM Identity Center | Account instance in this account. There is no Terraform resource for the instance itself. Users and groups are managed by Terraform in B. |
| GitHub repository | New private repository for the application manifests. Fine-grained PAT limited to it, Contents read-only. |
| GitHub OAuth App | For Dex login with a GitHub account. Callback `https://localhost:8080/api/dex/callback`. |
| Slack | App with a bot token (`chat:write`), invited to one channel. |
| Secrets Manager | Created by hand, read by name: `argocd/github-repo` (`username`, `password`), `argocd/dex-github` (client secret, plain text), `argocd/slack-token` (bot token, plain text). |

Secret values never appear in Terraform state, plan output or the assistant's context. Terraform
reads them with the ephemeral `aws_secretsmanager_secret_version` and writes them only to write-only
arguments (`data_wo`). The Slack token is resolved by CloudFormation with a dynamic reference,
because `aws_cloudwatch_event_connection` has no write-only argument.

## Layout

| Root | Owns | Providers |
| --- | --- | --- |
| `terraform/` (existing) | VPC, EKS, node group, add-ons | aws, tls |
| `gitops/` (new) | Argo CD, notifications pipeline, capability, IAM Identity Center users | aws, helm, kubernetes, alekc/kubectl |

`gitops/` reads the cluster with `data "aws_eks_cluster"` and authenticates with `aws eks get-token`
through the provider `exec` block, so a long apply does not outlive a token.

### Changes to `terraform/`

- `access_config` with `authentication_mode = "API_AND_CONFIG_MAP"`. The EKS API default is
  `CONFIG_MAP`, and the capability creates an access entry.
- Local tfvars during this work: two `t3.medium` on-demand nodes. `t3.small` allows 11 pods per node.

## A: self-managed Argo CD

- Chart `argo-cd` 10.17.1 (Argo CD v3.6.1) in namespace `gitops`, release `argo-cd`.
- Login through Dex with the GitHub connector. Local admin disabled. RBAC in `policy.csv` maps
  e-mail addresses to `role:admin`, scopes `[groups, email]`, no default role. The client secret is a
  Kubernetes Secret labelled `app.kubernetes.io/part-of: argocd` and referenced as
  `$argocd-dex-github:clientSecret`.
- `argocd-cm`: `kustomize.buildOptions: --load-restrictor LoadRestrictionsNone`. JSON logging.
- Repository Secret with the PAT (`username`, `password`), project-scoped to `default`.
- Applications as `kubectl_manifest`, project `default`, destination
  `server: https://kubernetes.default.svc`, finalizer `resources-finalizer.argocd.argoproj.io`:
  - `app-manual`: manual sync. Its overlay reads a `replacements` file outside the kustomization
    root, so it needs `--load-restrictor LoadRestrictionsNone`.
  - `app-auto`: automated sync with prune.
- Notifications: `awssqs` only, IRSA on the notifications controller, `TZ=Asia/Tokyo`, six custom
  triggers and templates. Each message is a Slack Block Kit array and prints the finish time with
  `.Local.Format` and with `dateInZone "Asia/Tokyo"`.
- Delivery to Slack on the AWS side: SQS queue, EventBridge Pipe, custom event bus, rule, API
  destination calling `chat.postMessage`. The connection and API destination are a CloudFormation
  stack so that the token stays a dynamic reference.

## B: migration commits

| Change | Official step |
| --- | --- |
| Helm values: controller, server, repo server and ApplicationSet at 0 replicas; Dex and the notifications controller disabled (the chart has no replica setting for them); `argocd-cm` no longer rendered | 2 |
| Capability role (trust `capabilities.eks.amazonaws.com`, `sts:AssumeRole`, `sts:TagSession`) with SQS and Secrets Manager permissions | 3 |
| IAM Identity Center user, group and membership | 3 |
| `aws_eks_capability`: `ARGOCD`, namespace `gitops`, the account instance, group mapped to `ADMIN`, `RETAIN`. Depends on the Helm release. | 3 |
| Access policy `AmazonEKSEditPolicy` for the application namespaces and a read-all ClusterRole bound to `eks-access-entry:<role ARN>` | 3 |
| `argocd-cm` and `argocd-notifications-cm` owned by Terraform with the labels the capability reads. Depend on the Helm release. | 4 |
| Repository Secret replaced by one with `secretArn` | 5 |
| Cluster Secret `in-cluster` with the cluster ARN | 7 |
| Applications use `destination.name: in-cluster` | 7, 8 |
| Capability log delivery (application and notification logs) | - |
| Last commit: Helm release, IRSA role and Dex Secret removed | 10 |

## Verification items

Each item is captured under `logs/<date>/` (git-ignored) with the commands and outputs.

1. `app-manual` after the migration, because `--load-restrictor` is not a supported build option.
2. Finish time in the Slack message: `.Local.Format` with `TZ` (A) and without it (B), and `dateInZone`.
3. Argo CD version of the capability compared with the chart, and the Helm-installed CRDs after the
   capability is created.
4. Takeover of deployed resources: tracking annotation, sync status, and whether prune deletes
   anything in `app-auto`.
5. `argocd-cm` and `argocd-notifications-cm` moving from Helm to Terraform within one apply.
6. Login: Dex with GitHub (A), IAM Identity Center (B), and the RBAC mapping in each.
7. Repository access: PAT in a Secret (A), `secretArn` (B).
8. `awssqs` delivery with the capability role, end to end to Slack.
9. A plan that replaces an Application with the finalizer (plan only).
10. Rollback from B to A.
11. Cost of each phase in ap-northeast-1.

## Cost (ap-northeast-1, approximate)

EKS control plane, one NAT Gateway, two t3.medium on-demand nodes, capability $0.037486 per hour
and $0.001853 per Application hour (price list published 2026-10-27), three Secrets Manager secrets,
SQS, EventBridge and CloudWatch Logs at test volume.

## Teardown

Apply the last commit of B, delete the Applications while the capability runs so the finalizer is
processed, `terraform destroy` in `gitops/`, then `make destroy`.

## Open risks

- The capability's Argo CD version is not documented and may be lower than v3.6.1.
- Behaviour when the capability installs CRDs over Helm-installed CRDs is not documented.
- Rollback to A removes Terraform-owned ConfigMaps and re-renders them in Helm in one apply. The
  order is not guaranteed and a second apply may be needed.
- AWS documents the automatic access entry permissions in two ways. The access policies are listed
  after the run.

## References

- https://docs.aws.amazon.com/eks/latest/userguide/argocd-comparison.html
- https://docs.aws.amazon.com/eks/latest/userguide/create-argocd-capability.html
- https://docs.aws.amazon.com/eks/latest/userguide/argocd-configure-settings.html
- https://docs.aws.amazon.com/eks/latest/userguide/argocd-notifications.html
- https://docs.aws.amazon.com/eks/latest/userguide/argocd-register-clusters.html
- https://docs.aws.amazon.com/eks/latest/userguide/integration-secrets-manager.html
- https://docs.aws.amazon.com/eks/latest/userguide/capability-role.html
- https://docs.aws.amazon.com/singlesignon/latest/userguide/account-instances-identity-center.html
- https://aws.amazon.com/about-aws/whats-new/2026/11/amazon-eks-argo-cd-notifications/
