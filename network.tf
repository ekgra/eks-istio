data "aws_availability_zones" "available" {
  state = "available"
}



resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.value.az
  cidr_block              = each.value.cidr
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "${var.cluster_name}-public-${each.value.az}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

resource "aws_route" "public_inet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public_assoc" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Extra node security group to attach to the Node Group later.
# NLB (instance mode) forwards traffic to NodePorts; source IP is the client,
# so nodes must allow NodePort range (lock to your IP/32 for safer testing).
resource "aws_security_group" "nodes_extra" {
  name        = "${var.cluster_name}-nodes-extra"
  description = "Additional SG for nodes to allow NodePort from allowed_cidr"
  vpc_id      = aws_vpc.this.id

  egress {
    description = "all egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Kubernetes default NodePort range 30000-32767
  ingress {
    description = "NodePort range for NLB instance targets"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  tags = {
    Name = "${var.cluster_name}-nodes-extra"
  }
}


# Allow EKS control plane (cluster SG) to reach kubelet on nodes (10250)
resource "aws_security_group_rule" "nodes_extra_from_cluster_10250" {
  type                     = "ingress"
  description              = "EKS control plane -- kubelet logs/exec"
  security_group_id        = aws_security_group.nodes_extra.id
  source_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
}

# (Optional) allow HTTPS 443 from control plane to nodes (used by some addons/webhooks)
resource "aws_security_group_rule" "nodes_extra_from_cluster_443" {
  type                     = "ingress"
  description              = "EKS control plane -- node HTTPS (defensive)"
  security_group_id        = aws_security_group.nodes_extra.id
  source_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
}

# Allow nodes (nodes_extra SG) to call API server (cluster SG) on 443
resource "aws_security_group_rule" "cluster_from_nodes_443" {
  type                     = "ingress"
  description              = "Nodes -- EKS API server (CoreDNS, controllers)"
  security_group_id        = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  source_security_group_id = aws_security_group.nodes_extra.id
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
}


# Allow EKS control plane to reach istiod webhook (Service 443 -> pod 15017)
resource "aws_security_group_rule" "nodes_extra_from_cluster_15017" {
  type                     = "ingress"
  description              = "EKS control plane -- istiod webhook (15017)"
  security_group_id        = aws_security_group.nodes_extra.id
  source_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  from_port                = 15017
  to_port                  = 15017
  protocol                 = "tcp"
}

resource "aws_security_group_rule" "nodes_extra_from_vpc_all" {
  type              = "ingress"
  description       = "Allow east-west within VPC (pods/nodes/CoreDNS/etc.)"
  security_group_id = aws_security_group.nodes_extra.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = [var.vpc_cidr] # 10.10.0.0/16
}




