# VPC, subnets, NAT gateways and routing for the EKS cluster.

locals {
  # AZs are hardcoded because ec2:DescribeAvailabilityZones may be restricted by SCP.
  availability_zones = {
    "ap-northeast-1" = ["ap-northeast-1a", "ap-northeast-1c"]
    "us-east-1"      = ["us-east-1a", "us-east-1b"]
    "us-west-2"      = ["us-west-2a", "us-west-2b"]
  }

  # EKS requires subnets in at least two AZs.
  # https://docs.aws.amazon.com/eks/latest/userguide/network-reqs.html
  current_azs = local.availability_zones[var.aws_region]
  az_count    = 2

  nat_gateway_count = var.single_nat_gateway ? 1 : local.az_count
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  # Both are required by EKS.
  # https://docs.aws.amazon.com/eks/latest/userguide/network-reqs.html
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name                                        = "${var.cluster_name}-vpc"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

# Public subnets host the NAT gateways and internet-facing load balancers.
resource "aws_subnet" "public" {
  count = local.az_count

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = local.current_azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "${var.cluster_name}-public-subnet-${count.index + 1}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    # Required for internet-facing load balancer auto discovery.
    # https://docs.aws.amazon.com/eks/latest/userguide/network-load-balancing.html
    "kubernetes.io/role/elb" = "1"
  }
}

# Worker nodes and control plane ENIs go here.
resource "aws_subnet" "private" {
  count = local.az_count

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = local.current_azs[count.index]

  tags = {
    Name                                        = "${var.cluster_name}-private-subnet-${count.index + 1}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    # Required for internal load balancer auto discovery.
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_eip" "nat" {
  count = local.nat_gateway_count

  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "${var.cluster_name}-eip-${count.index + 1}"
  }
}

# Outbound access for nodes in private subnets.
resource "aws_nat_gateway" "main" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.cluster_name}-nat-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

resource "aws_route_table" "private" {
  count = local.az_count

  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    # With one NAT gateway all AZs share it, otherwise each AZ uses its own.
    nat_gateway_id = aws_nat_gateway.main[min(count.index, local.nat_gateway_count - 1)].id
  }

  tags = {
    Name = "${var.cluster_name}-private-rt-${count.index + 1}"
  }
}

resource "aws_route_table_association" "public" {
  count = local.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count = local.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
