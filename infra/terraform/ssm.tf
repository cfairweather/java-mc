resource "aws_ssm_parameter" "rcon_password" {
  name  = "/${var.name}/rcon_password"
  type  = "SecureString"
  value = var.rcon_password
}

resource "aws_ssm_parameter" "restic_password" {
  name  = "/${var.name}/restic_password"
  type  = "SecureString"
  value = var.restic_password
}
