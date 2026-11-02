# AWS Client VPN: a managed OpenVPN server. Connect with any OpenVPN client
# (OpenVPN Connect, OpenVPN GUI, Tunnelblick) and reach every private IP in the VPC.
#
# Authentication is mutual TLS: Terraform creates a private CA, a server
# certificate and one client certificate per name in var.vpn_client_names.
# Get a client's ready-to-import profile with:
#   terraform output -json vpn_client_configs | jq -r '.["<name>"]' > <name>.ovpn
#
# The private keys are stored in Terraform state, so keep the state private.

# Certificate authority

resource "tls_private_key" "vpn_ca" {
  algorithm = "RSA"
  rsa_bits  = 2048 # Client VPN only accepts RSA 1024/2048 certificates
}

resource "tls_self_signed_cert" "vpn_ca" {
  private_key_pem = tls_private_key.vpn_ca.private_key_pem

  subject {
    common_name  = "${local.name_suffix}-vpn-ca"
    organization = var.project_name
  }

  is_ca_certificate     = true
  validity_period_hours = 87600 # 10 years
  allowed_uses          = ["cert_signing", "crl_signing"]
}

# Server certificate (presented by the VPN endpoint)

resource "tls_private_key" "vpn_server" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "vpn_server" {
  private_key_pem = tls_private_key.vpn_server.private_key_pem
  dns_names       = ["server.vpn.${var.project_name}.internal"]

  subject {
    common_name = "server.vpn.${var.project_name}.internal"
  }
}

resource "tls_locally_signed_cert" "vpn_server" {
  cert_request_pem   = tls_cert_request.vpn_server.cert_request_pem
  ca_private_key_pem = tls_private_key.vpn_ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.vpn_ca.cert_pem

  validity_period_hours = 43800 # 5 years
  allowed_uses          = ["digital_signature", "key_encipherment", "server_auth"]
}

resource "aws_acm_certificate" "vpn_server" {
  private_key       = tls_private_key.vpn_server.private_key_pem
  certificate_body  = tls_locally_signed_cert.vpn_server.cert_pem
  certificate_chain = tls_self_signed_cert.vpn_ca.cert_pem

  tags = {
    Name = "vpn-server-${local.name_suffix}"
  }
}

# Client certificates, one per person. Removing a name from var.vpn_client_names
# deletes its certificate, but the endpoint keeps trusting it until it expires:
# to cut someone off immediately you would also need a revocation list (CRL).

resource "tls_private_key" "vpn_client" {
  for_each = var.vpn_client_names

  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "vpn_client" {
  for_each = var.vpn_client_names

  private_key_pem = tls_private_key.vpn_client[each.key].private_key_pem

  subject {
    common_name = "${each.key}.vpn.${var.project_name}.internal"
  }
}

resource "tls_locally_signed_cert" "vpn_client" {
  for_each = var.vpn_client_names

  cert_request_pem   = tls_cert_request.vpn_client[each.key].cert_request_pem
  ca_private_key_pem = tls_private_key.vpn_ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.vpn_ca.cert_pem

  validity_period_hours = 8760 # 1 year
  early_renewal_hours   = 720  # re-issued on any apply in the last 30 days; re-download the profile
  allowed_uses          = ["digital_signature", "key_encipherment", "client_auth"]
}

# VPN endpoint

resource "aws_cloudwatch_log_group" "vpn" {
  name              = "/aws/client-vpn/${local.name_suffix}"
  retention_in_days = 90
}

resource "aws_security_group" "vpn" {
  name        = "vpn-${local.name_suffix}"
  description = "Client VPN endpoint; VPN traffic enters the VPC from this group"
  vpc_id      = aws_vpc.vpc_main.id

  tags = {
    Name = "vpn-${local.name_suffix}"
  }
}

resource "aws_vpc_security_group_egress_rule" "vpn_to_vpc" {
  security_group_id = aws_security_group.vpn.id
  ip_protocol       = "-1"
  cidr_ipv4         = var.vpc_cidr
  description       = "VPN clients to anything in the VPC"
}

resource "aws_ec2_client_vpn_endpoint" "vpn" {
  description            = "vpn-${local.name_suffix}"
  server_certificate_arn = aws_acm_certificate.vpn_server.arn
  client_cidr_block      = var.vpn_client_cidr
  vpc_id                 = aws_vpc.vpc_main.id
  security_group_ids     = [aws_security_group.vpn.id]

  # Only VPC traffic goes through the VPN; your normal internet traffic doesn't.
  split_tunnel = true

  # The VPC's own DNS resolver (VPC base + 2), so names like the internal
  # Kubernetes API load balancer resolve to private IPs.
  dns_servers = [cidrhost(var.vpc_cidr, 2)]

  transport_protocol    = "udp"
  vpn_port              = 443
  session_timeout_hours = 12

  # The client certificates are signed by the same CA as the server certificate,
  # so the server certificate's chain is also what clients are checked against.
  authentication_options {
    type                       = "certificate-authentication"
    root_certificate_chain_arn = aws_acm_certificate.vpn_server.arn
  }

  connection_log_options {
    enabled              = true
    cloudwatch_log_group = aws_cloudwatch_log_group.vpn.name
  }

  tags = {
    Name = "vpn-${local.name_suffix}"
  }
}

# Each associated subnet is billed per hour. One is enough to reach the whole
# VPC; add more keys ("b", "c") to var.vpn_subnet_keys to survive an AZ outage.
resource "aws_ec2_client_vpn_network_association" "vpn" {
  for_each = var.vpn_subnet_keys

  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.vpn.id
  subnet_id              = aws_subnet.private[each.key].id
}

resource "aws_ec2_client_vpn_authorization_rule" "vpc" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.vpn.id
  target_network_cidr    = var.vpc_cidr
  authorize_all_groups   = true
  description            = "Every VPN client may reach the whole VPC"
}

# Client profiles (.ovpn)

locals {
  # The endpoint DNS name starts with "*."; any prefix works, and a random
  # one (remote-random-hostname) avoids stale DNS caching between connections.
  vpn_remote = replace(aws_ec2_client_vpn_endpoint.vpn.dns_name, "/^\\*\\./", "")

  vpn_client_configs = {
    for name in var.vpn_client_names : name => <<-EOT
      client
      dev tun
      proto udp
      remote ${local.vpn_remote} 443
      remote-random-hostname
      resolv-retry infinite
      nobind
      remote-cert-tls server
      verify-x509-name ${tls_cert_request.vpn_server.subject[0].common_name} name
      cipher AES-256-GCM
      reneg-sec 0
      verb 3

      <ca>
      ${trimspace(tls_self_signed_cert.vpn_ca.cert_pem)}
      </ca>
      <cert>
      ${trimspace(tls_locally_signed_cert.vpn_client[name].cert_pem)}
      </cert>
      <key>
      ${trimspace(tls_private_key.vpn_client[name].private_key_pem)}
      </key>
    EOT
  }
}
