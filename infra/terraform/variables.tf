variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "name" {
  description = "Name prefix for every resource"
  type        = string
  default     = "java-mc"
}

variable "instance_type" {
  description = "EC2 instance type. 4 vCPU / 16 GiB matches the sizing in server/server.env (8G heap)."
  type        = string
  default     = "m7i.xlarge"
}

variable "data_volume_gb" {
  description = "Size of the Bottlerocket data volume (holds the world and docker images)"
  type        = number
  default     = 100
}

variable "image" {
  description = "Server image built from this repo's Dockerfile"
  type        = string
  default     = "ghcr.io/cfairweather/java-mc:latest"
}

variable "image_pull_secret_arn" {
  description = "Optional Secrets Manager secret ({username,password}) for pulling a private GHCR image. Leave empty for a public package."
  type        = string
  default     = ""
}

variable "backup_image" {
  description = "Backup sidecar image"
  type        = string
  default     = "itzg/mc-backup:2026.9.2"
}

variable "server_profile" {
  description = "core (server-side mods only, vanilla clients can join) or full (needs the client pack)"
  type        = string
  default     = "full"
  validation {
    condition     = contains(["core", "full"], var.server_profile)
    error_message = "server_profile must be core or full."
  }
}

variable "memory" {
  description = "JVM heap (itzg MEMORY). Overrides server/server.env."
  type        = string
  default     = "8G"
}

variable "container_memory_mb" {
  description = "Hard memory limit for the server container (heap + off-heap + JVM overhead)"
  type        = number
  default     = 11264
}

variable "admin_cidrs" {
  description = "CIDRs allowed to reach BlueMap (port 8100). The game port is open to everyone; the whitelist does the gating."
  type        = list(string)
  default     = []
}

variable "vpc_id" {
  description = "VPC to deploy into. Empty = the account's default VPC."
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "Public subnet for the instance. Empty = first subnet of the VPC."
  type        = string
  default     = ""
}

variable "backup_bucket_name" {
  description = "S3 bucket for restic backups. Empty = <name>-backups-<account id>."
  type        = string
  default     = ""
}

variable "backup_interval" {
  description = "How often the sidecar snapshots the world"
  type        = string
  default     = "2h"
}

variable "backup_retention" {
  description = "restic forget flags"
  type        = string
  default     = "--keep-last 10 --keep-hourly 24 --keep-daily 7 --keep-weekly 4 --keep-monthly 3"
}

variable "rcon_password" {
  description = "RCON password (stored in SSM Parameter Store as a SecureString)"
  type        = string
  sensitive   = true
}

variable "restic_password" {
  description = "restic repository password. Losing it means losing every backup; keep it in a password manager."
  type        = string
  sensitive   = true
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "tags" {
  description = "Extra tags for every resource"
  type        = map(string)
  default     = {}
}
