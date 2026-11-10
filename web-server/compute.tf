locals {
  # /etc/nginx/sites-available/<this>.conf, e.g. example.com.conf
  nextjs_site_name = length(var.nextjs_server_names) > 0 ? var.nextjs_server_names[0] : "nextjs-frontend"
}

data "aws_ami" "ubuntu_2404" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Your public key, installed for user "ubuntu". Connect to the VPN, then: ssh ubuntu@<private-ip>
resource "aws_key_pair" "web_server" {
  key_name   = "${local.name_prefix}-web-server"
  public_key = var.ssh_public_key
}

# The servers sit in private subnets with no public IP: visitors reach them only
# through CloudFront and the internal load balancer; they reach the internet via NAT.
resource "aws_instance" "web_server" {
  count = var.instance_count

  ami                         = data.aws_ami.ubuntu_2404.id
  instance_type               = "c8i.large" # 2 vCPU, 4 GiB;
  subnet_id                   = var.private_subnet_ids[count.index % length(var.private_subnet_ids)] # one per AZ
  vpc_security_group_ids      = [aws_security_group.web_server.id]
  key_name                    = aws_key_pair.web_server.key_name
  associate_public_ip_address = false

  # IMDSv2 only.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    encrypted             = true
    delete_on_termination = true
  }

  # replace() strips Windows line endings (CRLF), which would break bash on Linux.
  user_data = replace(templatefile("${path.module}/scripts/nginx.sh.tftpl", {
    vpc_cidr         = var.vpc_cidr
    nextjs_site_name = local.nextjs_site_name
    # The Next.js reverse-proxy site; empty when there are no upstreams.
    nextjs_site_conf = length(var.nextjs_upstreams) == 0 ? "" : templatefile("${path.module}/scripts/nextjs-site.conf.tftpl", {
      upstreams    = var.nextjs_upstreams
      server_names = var.nextjs_server_names
      app_port     = split(":", var.nextjs_upstreams[0])[1]
    })
  }), "\r\n", "\n")

  tags = {
    Name = "${local.name_prefix}-web-${count.index + 1}"
  }

  volume_tags = {
    Name = "${local.name_prefix}-web-${count.index + 1}-root"
  }

  lifecycle {
    ignore_changes = [
      ami,       # A newer Ubuntu AMI must never silently replace a running server.
      user_data, # Script edits only apply to new servers.
    ]
  }
}
