resource "aws_vpc_ipv4_cidr_block_association" "secondary_cidr" {
  vpc_id     = var.vpc_id
  cidr_block = var.secondary_cidr
}

resource "aws_subnet" "secondary_subnet" {
  vpc_id            = aws_vpc_ipv4_cidr_block_association.secondary_cidr.vpc_id
  map_public_ip_on_launch = false  # Ensuring the subnets are private

  for_each          = var.secondary_subnets
  availability_zone = each.key
  cidr_block        = each.value
  tags = {
    Name = "secondary-${each.key}"
  }
}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

resource "kubectl_manifest" "eniconfig" {
  for_each  = var.secondary_subnets

  yaml_body = <<-YAML
    apiVersion: crd.k8s.amazonaws.com/v1alpha1
    kind: ENIConfig
    metadata:
      name: ${each.key}
      namespace: default
    spec:
      securityGroups:
        - ${data.aws_eks_cluster.this.vpc_config[0].cluster_security_group_id}
      subnet: ${aws_subnet.secondary_subnet[each.key].id}
  YAML
}

resource "null_resource" "enable_custom_networking" {
  provisioner "local-exec" {
    command = "kubectl set env daemonset aws-node -n kube-system AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true ENI_CONFIG_LABEL_DEF=topology.kubernetes.io/zone ENABLE_PREFIX_DELEGATION=true WARM_PREFIX_TARGET=1"
  }
}

# Associate the secondary subnets with the existing private subnet route table
#resource "aws_route_table_association" "secondary_subnet_association" {
#  for_each         = aws_subnet.secondary_subnet
#  subnet_id        = each.value.id
#  route_table_id   = var.private_route_table_id
#}

# Associate the secondary subnets with their respective private subnet route tables
locals {
  subnet_count = length(keys(var.secondary_subnets))
}

resource "aws_route_table_association" "secondary_subnet_association" {
  count           = local.subnet_count

  subnet_id       = aws_subnet.secondary_subnet[keys(var.secondary_subnets)[count.index]].id

  route_table_id  = count.index % 2 == 0 ? var.private_route_table_id_1 : var.private_route_table_id_2
}


# Example variable values
variable "cluster_name" {
  default = "eks_cluster"
}

variable "vpc_id" {
  default = "vpc-0ad1b19b9c3aaaec0"
}

variable "secondary_cidr" {
  default = "100.64.0.0/16"
}

variable "secondary_subnets" {
  default = {
    eu-west-2a = "100.64.0.0/18"
    eu-west-2b = "100.64.64.0/18"
  }
}

variable "private_route_table_id_1" {
  default = "rtb-0e860edfd6b33cee4"  # Replace with your existing private subnet route table ID
}
variable "private_route_table_id_2" {
  default = "rtb-0e860edfd6b33cee4"  # Replace with your second existing private subnet route table ID
}
