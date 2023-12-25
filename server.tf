data "aws_ami" "latest-amazon-linux-image" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-kernel-*-hvm-*-x86_64-gp2"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "atlassian-server" {
  # ami                         = data.aws_ami.latest-amazon-linux-image.id
  ami                         = "ami-074413845c101fc4d"
  instance_type               = var.instance_type
  key_name                    = "atlassian-server-key"
  subnet_id                   = aws_subnet.atlassian-server-subnet-1.id
  vpc_security_group_ids      = [aws_default_security_group.default-sg.id]
  availability_zone           = var.availability_zone[0]
  associate_public_ip_address = true
  user_data                   = file("atlassian-server-setup.sh")
  root_block_device {
      volume_type           = "gp2"
      volume_size           = 300
      delete_on_termination = false
  }
  tags = {
    Name = "${var.env_prefix}-server"
  }
}

resource "aws_volume_attachment" "ebs_attachment" {
  volume_id          = aws_instance.atlassian-server.root_block_device[0].volume_id
  instance_id        = aws_instance.atlassian-server.id
  device_name        = aws_instance.atlassian-server.root_block_device[0].device_name
}

output "ec2_public_ip" {
  value = aws_instance.atlassian-server.public_ip
}

