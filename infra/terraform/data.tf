data "aws_caller_identity" "current" {}

data "aws_vpc" "this" {
  default = var.vpc_id == "" ? true : null
  id      = var.vpc_id == "" ? null : var.vpc_id
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }
  filter {
    name   = "default-for-az"
    values = var.subnet_id == "" && var.vpc_id == "" ? ["true"] : ["true", "false"]
  }
}

# Bottlerocket ECS-optimized AMI, always the latest release for this region.
data "aws_ssm_parameter" "bottlerocket_ami" {
  name = "/aws/service/bottlerocket/aws-ecs-2/x86_64/latest/image_id"
}

data "aws_kms_alias" "ssm" {
  name = "alias/aws/ssm"
}

locals {
  account_id    = data.aws_caller_identity.current.account_id
  subnet_id     = var.subnet_id != "" ? var.subnet_id : sort(data.aws_subnets.public.ids)[0]
  backup_bucket = var.backup_bucket_name != "" ? var.backup_bucket_name : "${var.name}-backups-${local.account_id}"

  # server/server.env and mods/versions.env are the single source of truth for
  # server settings, shared with compose.yaml. Parse KEY=VALUE lines.
  env_files = [
    "${path.module}/../../mods/versions.env",
    "${path.module}/../../server/server.env",
  ]
  env_lines = flatten([for f in local.env_files : split("\n", file(f))])
  env_from_files = {
    for line in local.env_lines :
    trimspace(split("=", line)[0]) => trimspace(join("=", slice(split("=", line), 1, length(split("=", line)))))
    if length(trimspace(line)) > 0 && !startswith(trimspace(line), "#") && strcontains(line, "=")
  }
  env_overrides = {
    MODRINTH_PROJECTS = "@/mods-list/server-mods.${var.server_profile}.txt"
    MODPACK_VERSION   = var.server_profile
    MEMORY            = var.memory
  }
  server_env = merge(local.env_from_files, local.env_overrides)
}
