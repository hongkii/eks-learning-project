# Launch template and EKS managed node group.
#
# When a launch template is attached, disk_size and remote_access cannot be set
# on the node group. Both are moved into the launch template.
# https://docs.aws.amazon.com/eks/latest/userguide/launch-templates.html

# Without image_id, EKS injects the AMI for ami_type and the bootstrap user data.
resource "aws_launch_template" "eks_nodes" {
  name_prefix = "${var.cluster_name}-node-"

  vpc_security_group_ids = [aws_security_group.eks_nodes.id]

  key_name = var.ec2_key_pair_name != "" ? var.ec2_key_pair_name : null

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.disk_size
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  # hop limit sets the TTL of the IMDSv2 PUT response, not the request.
  # https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-instance-metadata-service.html
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = var.imds_hop_limit
  }

  monitoring {
    enabled = false
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.cluster_name}-worker-node"
    }
  }

  tags = {
    Name = "${var.cluster_name}-node-template"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-node-group"
  node_role_arn   = aws_iam_role.eks_node_group.arn

  subnet_ids = aws_subnet.private[*].id

  # Kept separate from the cluster version so the control plane can be upgraded
  # first and the nodes left on N-1 during the bake period. While the nodes stay
  # on N-1 the kubelet version skew insight stays PASSING, so a rollback does not
  # need the node group to be rolled back first.
  # https://docs.aws.amazon.com/eks/latest/best-practices/rollback-cluster-upgrades.html
  version = coalesce(var.node_group_kubernetes_version, var.kubernetes_version)

  # AL2 is no longer supported from Kubernetes 1.33.
  # https://docs.aws.amazon.com/eks/latest/userguide/eks-optimized-ami.html
  ami_type = "AL2023_x86_64_STANDARD"

  # Allowed here only because the launch template does not set instance_type.
  instance_types = var.instance_types
  capacity_type  = var.capacity_type

  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = aws_launch_template.eks_nodes.latest_version
  }

  scaling_config {
    desired_size = var.node_group_desired_size
    max_size     = var.node_group_max_size
    min_size     = var.node_group_min_size
  }

  update_config {
    max_unavailable_percentage = 25
  }

  labels = {
    role        = "worker"
    environment = var.environment
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy,
  ]

  tags = {
    Name = "${var.cluster_name}-node-group"
  }

  lifecycle {
    # desired_size is managed by the autoscaling group.
    ignore_changes = [scaling_config[0].desired_size]
  }
}
