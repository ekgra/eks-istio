############################
# IAM for EKS control plane
############################
resource "aws_iam_role" "eks_cluster" {
  name               = "${var.cluster_name}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_assume_role.json
}

data "aws_iam_policy_document" "eks_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

############################
# EKS Cluster
############################
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.eks_version

  vpc_config {
    subnet_ids              = [for s in aws_subnet.public : s.id]
    endpoint_public_access  = true
    endpoint_private_access = false
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller
  ]

  tags = {
    Name = var.cluster_name
  }
}

############################
# IAM for Node Group
############################
resource "aws_iam_role" "node" {
  name               = "${var.cluster_name}-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json
}

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_ro" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

############################
# Launch Template (to add public IP + extra SG)
############################
# EKS will automatically add its own managed SGs; this LT adds your extra SG too.
# Ensure associate_public_ip_address = true so nodes in public subnets get public IPs.
resource "aws_launch_template" "node_lt" {
  name_prefix = "${var.cluster_name}-lt-"

  network_interfaces {
    # Include ONLY your additional SG here; EKS will append the cluster-managed SGs.
    security_groups             = [aws_security_group.nodes_extra.id]
    associate_public_ip_address = true
  }

  # Keep it minimal; instance type is set on the node group.
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.cluster_name}-node"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

############################
# Managed Node Group (Spot)
############################
resource "aws_eks_node_group" "spot_ng" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-ng-spot"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = [for s in aws_subnet.public : s.id]
  capacity_type   = "SPOT"

  scaling_config {
    desired_size = var.node_desired
    max_size     = var.node_max
    min_size     = var.node_min
  }

  instance_types = var.instance_types

  launch_template {
    id      = aws_launch_template.node_lt.id
    version = "$Latest"
  }

  update_config {
    max_unavailable = 1
  }

  tags = {
    Name = "${var.cluster_name}-ng-spot"
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_ro
  ]
}

############################
# Managed Node Group (On-Demand fallback)
############################
resource "aws_eks_node_group" "od_ng" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-ng-od"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = [for s in aws_subnet.public : s.id]
  capacity_type   = "ON_DEMAND"

  # Keep this at zero so you don't pay unless needed. 
  # Manual fallback: set desired_size to 2 if Spot is unavailable.
  scaling_config {
    desired_size = var.od_node_desired
    max_size     = var.od_node_max
    min_size     = var.od_node_min
  }

  instance_types = var.od_instance_types

  launch_template {
    id      = aws_launch_template.node_lt.id
    version = "$Latest"
  }

  update_config { max_unavailable = 1 }

  tags = {
    Name = "${var.cluster_name}-ng-od"
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_ro
  ]
}
