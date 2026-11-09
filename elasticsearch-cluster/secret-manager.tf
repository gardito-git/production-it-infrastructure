# Everything secret the nodes need at boot: built-in user passwords and Kibana's
# encryption keys. Nodes read it with their IAM role, so none of it is in user
# data. It's in Terraform state too. (No certificates: there are none to manage.)

# special = false: these end up in YAML, keystores and URLs, where some special
# characters need escaping. 32 letters and digits is still ~190 bits of entropy.
resource "random_password" "elastic" {
  length  = 32
  special = false
}

resource "random_password" "kibana_system" {
  length  = 32
  special = false
}

# Kibana needs three keys of at least 32 characters, one per feature.
resource "random_password" "kibana_encryption" {
  for_each = toset(["encryptedSavedObjects", "security", "reporting"])

  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "elasticsearch" {
  # name_prefix adds a random suffix: a deleted secret's name stays reserved for
  # the recovery window, so a fixed name would block destroy + re-create.
  name_prefix             = "${local.name_prefix}/elasticsearch/"
  description             = "Elasticsearch cluster ${local.name_prefix}: passwords and Kibana keys"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "elasticsearch" {
  secret_id = aws_secretsmanager_secret.elasticsearch.id
  secret_string = jsonencode({
    elastic_username       = "elastic"
    elastic_password       = random_password.elastic.result
    kibana_system_password = random_password.kibana_system.result

    # Field names match the Kibana settings, dots replaced by underscores (kibana.sh).
    kibana_xpack_encryptedSavedObjects_encryptionKey = random_password.kibana_encryption["encryptedSavedObjects"].result
    kibana_xpack_security_encryptionKey              = random_password.kibana_encryption["security"].result
    kibana_xpack_reporting_encryptionKey             = random_password.kibana_encryption["reporting"].result

    # For applications:
    hosts = [for ip in local.data_ips : "http://${ip}:9200"]
  })
}
