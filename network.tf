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
