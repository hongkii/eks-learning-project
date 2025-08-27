# =============================================================================
# VPC 및 네트워킹 리소스 정의
# =============================================================================
# 이 파일은 EKS 클러스터를 위한 네트워킹 인프라를 생성합니다.
# - VPC 및 서브넷 생성 (퍼블릭/프라이빗)
# - 인터넷 게이트웨이 및 NAT 게이트웨이
# - 라우팅 테이블 및 연결
# - EKS 베스트 프랙티스: 워커 노드를 프라이빗 서브넷에 배치
# - Multi-AZ 고가용성 구성
# =============================================================================

# AZ 목록을 직접 지정 (SCP 제한 우회)
locals {
  availability_zones = {
    "ap-northeast-1" = ["ap-northeast-1a", "ap-northeast-1c"]
    "us-east-1"      = ["us-east-1a", "us-east-1b"]
    "us-west-2"      = ["us-west-2a", "us-west-2b"]
  }
  # 항상 2개의 AZ를 사용 (최소 요구사항)
  current_azs = local.availability_zones[var.aws_region]
  az_count    = 2
}

# EKS 클러스터와 노드 그룹이 사용할 격리된 VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true # EKS 요구사항: 노드와 파드 간 DNS 해석
  enable_dns_support   = true # EKS 요구사항: ELB 및 서비스 디스커버리

  tags = {
    Name                                        = "${var.cluster_name}-vpc"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared" # EKS 보안그룹 자동 생성용
  }
}

# NAT Gateway와 ALB/NLB가 인터넷 접근에 사용
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

# NAT Gateway와 퍼블릭 LB 전용 서브넷 - EKS 노드는 배치되지 않음
resource "aws_subnet" "public" {
  count = local.az_count

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = local.current_azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "${var.cluster_name}-public-subnet-${count.index + 1}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1" # ALB/CLB 자동 배치용
  }
}

# EKS 베스트 프랙티스: 워커 노드와 컨트롤 플레인 ENI를 프라이빗 서브넷에 배치
resource "aws_subnet" "private" {
  count = local.az_count

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10) # 퍼블릭과 CIDR 분리
  availability_zone = local.current_azs[count.index]

  tags = {
    Name                                        = "${var.cluster_name}-private-subnet-${count.index + 1}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared" # EKS 서브넷 디스커버리
    "kubernetes.io/role/internal-elb"           = "1"      # NLB/ALB 내부 스킴 자동 배치
  }
}

# NAT Gateway용 고정 IP - 워커 노드의 아웃바운드 통신에 사용
resource "aws_eip" "nat" {
  count = local.az_count

  domain     = "vpc"
  depends_on = [aws_internet_gateway.main] # IGW 생성 후 EIP 할당

  tags = {
    Name = "${var.cluster_name}-eip-${count.index + 1}"
  }
}

# EKS 노드의 아웃바운드 통신용 NAT Gateway (AZ별 장애 격리)
resource "aws_nat_gateway" "main" {
  count = local.az_count

  allocation_id = aws_eip.nat[count.index].id       # 고정 IP 매핑
  subnet_id     = aws_subnet.public[count.index].id # 퍼블릭 서브넷에 배치

  tags = {
    Name = "${var.cluster_name}-nat-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.main]
}

# 퍼블릭 서브넷의 IGW 라우팅 테이블
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id # 모든 트래픽을 IGW로 라우팅
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

# 프라이빗 서브넷의 NAT Gateway 라우팅 (AZ별 장애 격리)
resource "aws_route_table" "private" {
  count = local.az_count

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id # 동일 AZ NAT GW 사용
  }

  tags = {
    Name = "${var.cluster_name}-private-rt-${count.index + 1}"
  }
}

# 퍼블릭 서브넷과 라우팅 테이블 연결
resource "aws_route_table_association" "public" {
  count = local.az_count

  subnet_id      = aws_subnet.public[count.index].id # NAT GW가 위치한 서브넷
  route_table_id = aws_route_table.public.id         # IGW 라우팅 테이블
}

# 프라이빗 서브넷과 라우팅 테이블 연결 (EKS 노드 배치 서브넷)
resource "aws_route_table_association" "private" {
  count = local.az_count

  subnet_id      = aws_subnet.private[count.index].id      # EKS 노드가 배치된 서브넷
  route_table_id = aws_route_table.private[count.index].id # 동일 AZ NAT GW 라우팅
}
