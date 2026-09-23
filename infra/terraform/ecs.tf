resource "aws_ecs_cluster" "this" {
  name = var.name
}

resource "aws_cloudwatch_log_group" "server" {
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days
}

locals {
  mc_container = merge({
    name              = "mc"
    image             = var.image
    essential         = true
    memory            = var.container_memory_mb
    memoryReservation = floor(var.container_memory_mb * 0.8)
    environment       = [for k, v in local.server_env : { name = k, value = v }]
    secrets = [
      { name = "RCON_PASSWORD", valueFrom = aws_ssm_parameter.rcon_password.arn },
    ]
    portMappings = [
      { containerPort = 25565, hostPort = 25565, protocol = "tcp" },
      { containerPort = 8100, hostPort = 8100, protocol = "tcp" },
    ]
    mountPoints = [{ sourceVolume = "mc-data", containerPath = "/data", readOnly = false }]
    healthCheck = {
      command     = ["CMD", "mc-health"]
      interval    = 60
      timeout     = 10
      retries     = 5
      startPeriod = 300
    }
    stopTimeout     = 120
    linuxParameters = { initProcessEnabled = true }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.server.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "mc"
      }
    }
    }, var.image_pull_secret_arn != "" ? {
    repositoryCredentials = { credentialsParameter = var.image_pull_secret_arn }
  } : {})

  backup_container = {
    name              = "backup"
    image             = var.backup_image
    essential         = false
    memory            = 768
    memoryReservation = 256
    environment = [
      { name = "BACKUP_METHOD", value = "restic" },
      { name = "RESTIC_REPOSITORY", value = "s3:s3.${var.region}.amazonaws.com/${aws_s3_bucket.backups.bucket}/restic" },
      { name = "AWS_DEFAULT_REGION", value = var.region },
      { name = "RESTIC_HOST", value = var.name },
      { name = "BACKUP_INTERVAL", value = var.backup_interval },
      { name = "INITIAL_DELAY", value = "5m" },
      { name = "PRUNE_RESTIC_RETENTION", value = var.backup_retention },
      { name = "PAUSE_IF_NO_PLAYERS", value = "true" },
      { name = "PLAYERS_ONLINE_CHECK_INTERVAL", value = "5m" },
      { name = "RCON_HOST", value = "localhost" },
      { name = "RCON_PORT", value = lookup(local.server_env, "RCON_PORT", "25575") },
      { name = "EXCLUDES", value = "*.jar,cache,logs,libraries,versions,.fabric,bluemap/web/maps" },
      { name = "TZ", value = lookup(local.server_env, "TZ", "UTC") },
    ]
    secrets = [
      { name = "RCON_PASSWORD", valueFrom = aws_ssm_parameter.rcon_password.arn },
      { name = "RESTIC_PASSWORD", valueFrom = aws_ssm_parameter.restic_password.arn },
    ]
    mountPoints     = [{ sourceVolume = "mc-data", containerPath = "/data", readOnly = true }]
    dependsOn       = [{ containerName = "mc", condition = "HEALTHY" }]
    linuxParameters = { initProcessEnabled = true }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.server.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "backup"
      }
    }
  }
}

resource "aws_ecs_task_definition" "server" {
  family                   = var.name
  requires_compatibilities = ["EC2"]
  # Host networking: no NAT overhead, and the backup sidecar reaches RCON on
  # localhost. Only 25565 and 8100 are reachable thanks to the security group.
  network_mode       = "host"
  execution_role_arn = aws_iam_role.execution.arn
  task_role_arn      = aws_iam_role.task.arn

  container_definitions = jsonencode([local.mc_container, local.backup_container])

  # The world lives in a Docker volume on the Bottlerocket data volume.
  volume {
    name = "mc-data"
    docker_volume_configuration {
      scope         = "shared"
      autoprovision = true
      driver        = "local"
    }
  }
}

resource "aws_ecs_service" "server" {
  name            = var.name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.server.arn
  desired_count   = 1
  launch_type     = "EC2"

  # Single host, fixed ports: the old task must stop before the new one starts.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  enable_execute_command             = true

  depends_on = [aws_instance.server, aws_iam_role_policy.task]
}
