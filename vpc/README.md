# VPC and VPN

A VPC across 3 availability zones, plus an AWS Client VPN so you can reach every
private IP from your laptop with the OpenVPN desktop app.

| Resource | Details |
|---|---|
| VPC | `10.0.0.0/16` (`vpc_cidr`), DNS hostnames on |
| Public subnets | `10.0.1.0/24`, `10.0.2.0/24`, `10.0.3.0/24`, routed to the internet gateway |
| Private subnets | `10.0.101.0/24`, `10.0.102.0/24`, `10.0.103.0/24`, routed to one NAT gateway |
| S3 gateway endpoint | Free; S3 traffic from private subnets skips the NAT gateway |
| Client VPN | OpenVPN-compatible, certificate login, split tunnel, VPN clients get `172.16.0.0/22` |

## Files

| File | What's in it |
|---|---|
| `main.tf` | VPC, subnets, internet gateway, NAT gateway, route tables, S3 endpoint |
| `vpn.tf` | Certificates, the Client VPN endpoint, its security group and the `.ovpn` profiles |
| `versions.tf` | Providers this module needs (`aws`, `tls`) |
| `variables.tf` / `outputs.tf` | Module inputs and outputs |

## Connecting with OpenVPN

1. Add yourself to `vpn_client_names` in `terraform.tfvars` (one profile is created per name), then apply:

   ```hcl
   vpn_client_names = ["gardito"]
   ```

2. Save your profile. It contains your private key, so keep it out of git
   (`*.ovpn` is in `.gitignore`):

   ```bash
   terraform output -json vpn_client_configs | jq -r '.gardito' > gardito.ovpn
   ```

   No `jq`? Run `terraform output vpn_client_configs` and copy your entry into a file.

3. Import `gardito.ovpn` into **OpenVPN Connect** (or OpenVPN GUI / Tunnelblick) and connect.

4. SSH to any node by its private IP:

   ```bash
   ssh ubuntu@10.0.101.10
   ```

Only VPC traffic goes through the tunnel (split tunnel), so the rest of your internet
traffic is unaffected. DNS for VPC names, like the Kubernetes API load balancer, is
answered by the VPC resolver, so those names resolve to private IPs while you're connected.

## Adding or removing people

- **Add:** add a name to `vpn_client_names`, apply, and send them their `.ovpn` securely.
- **Remove:** delete the name and apply. Its certificate is deleted, but **the endpoint
  still accepts it until it expires (1 year)**. To lock someone out immediately you need a
  certificate revocation list (CRL), which isn't set up yet.
- **Renewal:** client certificates are re-issued on any `terraform apply` within 30 days
  of expiry. After that, everyone downloads their profile again.

## Security notes

- **Login is by certificate only.** Anyone who has an `.ovpn` file can connect, so treat
  each file like a password and give every person their own.
- **The CA, server and client private keys are in Terraform state.** Keep the state private,
  and move it to an encrypted S3 backend before sharing this project.
- **Connections are logged** to CloudWatch Logs (`/aws/client-vpn/<project>-<env>`, kept 90 days).
- **SSH is allowed only from the VPN's security group**, so nodes accept no SSH from anywhere else.

## Cost

Client VPN is billed per hour for each associated subnet, plus per hour for each
connected client (about $0.10 and $0.05 per hour in most regions; check
[the pricing page](https://aws.amazon.com/vpn/pricing/) for yours). By default only
subnet `a` is associated. Add `"b"`, `"c"` to `vpn_subnet_keys` if the VPN must
survive an AZ outage, at extra cost.

## Inputs

| Name | Default | Description |
|---|---|---|
| `region` | (required) | AWS region, used for AZ names and the S3 endpoint |
| `project_name` | (required) | Used in resource names |
| `environment` | (required) | Used in resource names |
| `vpc_cidr` | `"10.0.0.0/16"` | VPC CIDR |
| `vpn_client_names` | (required) | One VPN certificate and profile per name |
| `vpn_client_cidr` | `"172.16.0.0/22"` | VPN client IPs. Must not overlap the VPC or Kubernetes pod/service CIDRs |
| `vpn_subnet_keys` | `["a"]` | Private subnets the VPN is attached to |

## Outputs

| Name | Description |
|---|---|
| `vpc_id`, `vpc_cidr` | The VPC |
| `public_subnet_ids`, `private_subnet_ids`, `private_subnet_cidrs` | Subnets, in a/b/c order |
| `vpn_endpoint_id` | Client VPN endpoint ID |
| `vpn_security_group_id` | Allow this group in other security groups to let VPN users in |
| `vpn_client_configs` | Sensitive. Map of name to `.ovpn` profile |
