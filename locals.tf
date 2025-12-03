locals {
  # pick two AZs deterministically
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # carve two /20 public subnets out of the /16
  public_subnets = {
    a = {
      az   = local.azs[0]
      cidr = cidrsubnet(var.vpc_cidr, 4, 0) # /20
    }
    b = {
      az   = local.azs[1]
      cidr = cidrsubnet(var.vpc_cidr, 4, 1) # /20
    }
  }
}