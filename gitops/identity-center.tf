# The capability signs users in through IAM Identity Center only. Terraform has no resource for
# the instance itself, so the account instance is created once by hand.
# https://docs.aws.amazon.com/singlesignon/latest/userguide/account-instances-identity-center.html
data "aws_ssoadmin_instances" "this" {}

locals {
  idc_instance_arn  = one(data.aws_ssoadmin_instances.this.arns)
  identity_store_id = one(data.aws_ssoadmin_instances.this.identity_store_ids)
}

resource "aws_identitystore_user" "argocd_admin" {
  identity_store_id = local.identity_store_id
  user_name         = var.idc_user.user_name
  display_name      = "${var.idc_user.given_name} ${var.idc_user.family_name}"

  name {
    given_name  = var.idc_user.given_name
    family_name = var.idc_user.family_name
  }

  emails {
    value   = var.idc_user.email
    primary = true
  }
}

resource "aws_identitystore_group" "argocd_admins" {
  identity_store_id = local.identity_store_id
  display_name      = "argocd-admins"
  description       = "Mapped to the ADMIN role of the Argo CD capability"
}

resource "aws_identitystore_group_membership" "argocd_admin" {
  identity_store_id = local.identity_store_id
  group_id          = aws_identitystore_group.argocd_admins.group_id
  member_id         = aws_identitystore_user.argocd_admin.user_id
}
