# Argo CD capability migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a self-managed Argo CD (branch A) and the commits that migrate it to the EKS Capability for Argo CD (branch B), both in Terraform.

**Architecture:** A new root `gitops/` holds everything Argo CD on top of the existing `terraform/` cluster root. Branch A installs the Helm chart; branch B adds the capability and moves the Argo CD objects to it while the Helm release stays at zero replicas. The last commit on B removes the Helm release.

**Tech Stack:** Terraform 1.15, providers aws 6.72, helm 3.3, kubernetes 3.5, alekc/kubectl 3.0, argo-cd chart 10.17.1 (Argo CD v3.6.1), CloudFormation (one stack), EventBridge Pipes.

**Spec:** `docs/superpowers/specs/2026-11-06-argocd-capability-migration-design.md`

## Global Constraints

- AWS profile `cm-yim.hongki`, region `ap-northeast-1`, cluster `my-study-eks`.
- Argo CD namespace `gitops`, Helm release `argo-cd`, application namespaces `demo-auto` and `demo-manual`.
- One secret is created by hand: `argocd/slack-token` (plain text). It reaches AWS only through a CloudFormation dynamic reference.
- Manifests are `argocd-demo/` in this public repository. Login on A is a local account managed in Terraform (IAM Identity Center SAML needs an organization instance, which this account does not manage).
- Comments, descriptions and docs in English, official facts only, short. Commits are one English line, `emoji: text`, no AI attribution.
- Before each commit: `terraform fmt -recursive -check` and `terraform validate` in every changed root.

## Testing approach

Terraform has no unit tests here. Each task is checked with `terraform validate` and `terraform fmt -check`, then with `terraform plan` once a session exists, and finally with the apply and the cluster checks listed per task. Runtime checks are recorded under `logs/<date>/`.

---

## Branch A: `feat/argocd-self-managed`

### Task 1: Cluster access entries and node size

**Files:**
- Modify: `terraform/eks.tf` (`aws_eks_cluster.main`)
- Modify (local, git-ignored): `terraform/terraform.tfvars`

- [ ] Add `access_config { authentication_mode = "API_AND_CONFIG_MAP", bootstrap_cluster_creator_admin_permissions = true }`.
- [ ] tfvars: `instance_types = ["t3.medium"]`, `capacity_type = "ON_DEMAND"`.
- [ ] `cd terraform && terraform validate && terraform fmt -check`.
- [ ] Commit `✨: enable access entries on the cluster`.
- [ ] After a session exists: `make deploy-all`, then `aws eks describe-cluster --name my-study-eks --query cluster.accessConfig` shows `API_AND_CONFIG_MAP`.

### Task 2: `gitops/` root, providers and namespaces

**Files:**
- Create: `gitops/versions.tf`, `gitops/providers.tf`, `gitops/variables.tf`, `gitops/namespaces.tf`, `gitops/outputs.tf`, `gitops/terraform.tfvars.example`

**Interfaces:**
- Produces: `data.aws_eks_cluster.this`, `kubernetes_namespace_v1.argocd`, `kubernetes_namespace_v1.apps["demo-auto"|"demo-manual"]`, `local.applications` (map of name to `{ namespace, path, sync_policy }`), variables `aws_region`, `cluster_name`, `repo_url`, `target_revision`, `argocd_user`, `slack_channel_id`.

- [ ] Providers authenticate with `exec` running `aws eks get-token`.
- [ ] `terraform init -backend=false && terraform validate`.
- [ ] Commit `✨: add a gitops root for Argo CD`.

### Task 3: Notifications pipeline to Slack

**Files:**
- Create: `gitops/notifications.tf`, `gitops/slack.tf`, `gitops/cfn/slack-api-destination.yaml.tftpl`, `gitops/notifications/block-kit.json.tftpl`

**Interfaces:**
- Produces: `aws_sqs_queue.notifications`, `local.notifications_services`, `local.notifications_templates`, `local.notifications_triggers` (maps of ConfigMap keys to strings), `local.notification_subscriptions` (annotation map), `aws_iam_role.notifications` (IRSA).

- [ ] SQS queue (SSE-SQS), EventBridge Pipe to a custom bus, rule with input transformer, CloudFormation stack for the connection and API destination, rule target with an invoke role.
- [ ] Six triggers and templates; message is a Block Kit array with the finish time in `.Local.Format` and `dateInZone`.
- [ ] Validate, fmt, commit `✨: send Argo CD notifications to Slack through SQS and EventBridge`.

### Task 4: Argo CD from the Helm chart

**Files:**
- Create: `gitops/argocd.tf`, `gitops/helm/values.yaml`

**Interfaces:**
- Consumes: Task 2 namespaces and variables, Task 3 notification locals and IRSA role.
- Produces: `helm_release.argocd`, `random_password.argocd_user`.

- [ ] Chart 10.17.1, Dex and admin disabled, local account `accounts.<argocd_user>: login` mapped to `role:admin`, bcrypt hash of a `random_password` through `set_sensitive`, `kustomize.buildOptions: --load-restrictor LoadRestrictionsNone`, JSON logs, notifications values from Task 3.
- [ ] Validate, fmt, commit.

### Task 5: Applications

**Files:**
- Create: `gitops/applications.tf`

**Interfaces:**
- Consumes: `local.applications`, `local.notification_subscriptions`, `helm_release.argocd`.
- Produces: `kubectl_manifest.application["app-auto"|"app-manual"]`.

- [ ] Destination `server: https://kubernetes.default.svc`, project `default`, finalizer, `app-auto` automated with prune, `app-manual` manual.
- [ ] Validate, fmt, commit `✨: add the demo Applications`.

### Task 6: Demo manifests

**Files:**
- Create: `argocd-demo/base/kustomization.yaml`, `argocd-demo/base/deployment.yaml`, `argocd-demo/base/service.yaml`, `argocd-demo/base/replacements/greeting.yaml`, `argocd-demo/env/auto/kustomization.yaml`, `argocd-demo/env/manual/kustomization.yaml`

- [ ] `env/manual` uses `replacements: - path: ../../base/replacements/greeting.yaml`, which needs `--load-restrictor LoadRestrictionsNone`.
- [ ] `kustomize build env/manual` fails, `kustomize build --load-restrictor LoadRestrictionsNone env/manual` succeeds.

### Task 7: Make targets and README

**Files:**
- Modify: `Makefile`, `README.md`

- [ ] Targets `gitops-init`, `gitops-plan`, `gitops-apply`, `gitops-destroy`, `argocd-ui`, `argocd-apps`, all logging to `logs/` like the existing targets.
- [ ] README section for the migration.
- [ ] Commit `🔧: add make targets for the gitops root`, `📝: document the Argo CD migration`.

### Task 8: Apply A and check

- [ ] `make gitops-init && make gitops-apply AUTO_APPROVE=1`.
- [ ] `make argocd-password`, `make argocd-ui`, log in as the local account, both Applications visible; sync `app-manual`; `app-auto` synced.
- [ ] A Slack message arrives with both times in JST.
- [ ] Record in `logs/<date>/`.

## Branch B: `feat/argocd-capability` (fast-forwarded to A)

### Task 9: Scale the Helm release down and move the ConfigMaps

**Files:**
- Create: `gitops/helm/scaled-down-values.yaml`, `gitops/argocd-config.tf`
- Modify: `gitops/argocd.tf`, `gitops/notifications.tf`

- [ ] Replicas 0 for controller, server, repo server, ApplicationSet; notifications disabled; `configs.cm.create: false`.
- [ ] `kubernetes_config_map_v1` for `argocd-cm` (label `app.kubernetes.io/part-of: argocd`) and `argocd-notifications-cm` (label `eks.amazonaws.com/managed-notifications: "enabled"`), both `depends_on = [helm_release.argocd]`.
- [ ] Commit `♻️: scale the self-managed Argo CD to zero and own its ConfigMaps in terraform`.

### Task 10: Capability, IAM Identity Center and cluster access

**Files:**
- Create: `gitops/capability.tf`, `gitops/identity-center.tf`, `gitops/capability-access.tf`
- Modify: `gitops/variables.tf`, `gitops/outputs.tf`, `gitops/terraform.tfvars.example`

- [ ] Capability role and policy, `aws_eks_capability` (`ARGOCD`, namespace `gitops`, account instance, group as `ADMIN`, `RETAIN`, `depends_on = [helm_release.argocd]`).
- [ ] `aws_identitystore_user`, `aws_identitystore_group`, `aws_identitystore_group_membership`.
- [ ] `AmazonEKSEditPolicy` on the application namespaces, read-all ClusterRole bound to `eks-access-entry:<role ARN>`.
- [ ] Capability log delivery for application and notification logs.
- [ ] Commit `✨: create the EKS capability for Argo CD`.

### Task 11: Register the cluster and move repositories and Applications

**Files:**
- Modify: `gitops/applications.tf`
- Create: `gitops/cluster.tf`

- [ ] Cluster Secret `in-cluster` with the cluster ARN.
- [ ] Applications use `destination.name: in-cluster` and depend on the capability.
- [ ] Commit `✨: point the repository and Applications at the capability`.

### Task 12: Apply B and check

- [ ] `make gitops-apply AUTO_APPROVE=1` on B.
- [ ] Verification items 1 to 9 of the spec, recorded in `logs/<date>/`.
- [ ] Rollback: check out A, apply, record; check out B, apply again.

### Task 13: Decommission (last commit on B)

**Files:**
- Modify: `gitops/argocd.tf`, `gitops/argocd-config.tf`, `gitops/capability.tf`, `gitops/notifications.tf`
- Delete: `gitops/helm/`

- [ ] Remove `helm_release.argocd`, the IRSA role, the local account password and the `depends_on` that point at them.
- [ ] Commit `🔥: remove the self-managed Argo CD`, apply, check that the Applications stay synced.
