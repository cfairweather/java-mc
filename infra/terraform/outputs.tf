output "server_address" {
  description = "What friends type into Multiplayer > Direct Connect"
  value       = aws_eip.server.public_ip
}

output "bluemap_url" {
  value = "http://${aws_eip.server.public_ip}:8100/"
}

output "instance_id" {
  value = aws_instance.server.id
}

output "region" {
  value = var.region
}

output "ecs_cluster" {
  value = aws_ecs_cluster.this.name
}

output "ecs_service" {
  value = aws_ecs_service.server.name
}

output "log_group" {
  value = aws_cloudwatch_log_group.server.name
}

output "backup_bucket" {
  value = aws_s3_bucket.backups.bucket
}
