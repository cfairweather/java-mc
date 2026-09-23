# One Bottlerocket host registered into the ECS cluster. Bottlerocket has no
# SSH and no package manager; use `make aws-ssm` for a host shell and ECS Exec
# for the containers.
resource "aws_instance" "server" {
  ami                    = data.aws_ssm_parameter.bottlerocket_ami.value
  instance_type          = var.instance_type
  subnet_id              = local.subnet_id
  vpc_security_group_ids = [aws_security_group.server.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name

  user_data = <<-TOML
    [settings.ecs]
    cluster = "${aws_ecs_cluster.this.name}"
    container-stop-timeout = "2m"

    [settings.kernel]
    lockdown = "integrity"
  TOML

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  # Bottlerocket root volume (OS image, immutable).
  root_block_device {
    volume_type = "gp3"
    encrypted   = true
  }

  # Bottlerocket data volume: container images, docker volumes (the world).
  ebs_block_device {
    device_name           = "/dev/xvdb"
    volume_type           = "gp3"
    volume_size           = var.data_volume_gb
    encrypted             = true
    delete_on_termination = false
  }

  tags = { Name = "${var.name}-server" }

  lifecycle {
    # A new AMI must not silently replace the instance (and its data volume).
    ignore_changes = [ami]
  }
}
