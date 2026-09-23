resource "aws_security_group" "server" {
  name        = "${var.name}-server"
  description = "Minecraft server host"
  vpc_id      = data.aws_vpc.this.id
}

# Game port: open to the world. Authentication is Mojang's, authorization is
# the whitelist.
resource "aws_vpc_security_group_ingress_rule" "minecraft_v4" {
  security_group_id = aws_security_group.server.id
  description       = "Minecraft"
  ip_protocol       = "tcp"
  from_port         = 25565
  to_port           = 25565
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "minecraft_v6" {
  security_group_id = aws_security_group.server.id
  description       = "Minecraft"
  ip_protocol       = "tcp"
  from_port         = 25565
  to_port           = 25565
  cidr_ipv6         = "::/0"
}

# BlueMap: admin networks only.
resource "aws_vpc_security_group_ingress_rule" "bluemap" {
  for_each          = toset(var.admin_cidrs)
  security_group_id = aws_security_group.server.id
  description       = "BlueMap"
  ip_protocol       = "tcp"
  from_port         = 8100
  to_port           = 8100
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "all_v4" {
  security_group_id = aws_security_group.server.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "all_v6" {
  security_group_id = aws_security_group.server.id
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
}

resource "aws_eip" "server" {
  domain = "vpc"
  tags   = { Name = "${var.name}-server" }
}

resource "aws_eip_association" "server" {
  instance_id   = aws_instance.server.id
  allocation_id = aws_eip.server.id
}
