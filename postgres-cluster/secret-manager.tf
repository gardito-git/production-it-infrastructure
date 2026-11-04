resource "random_password" "db_password" {
  length           = 16
  special          = false
  upper            = true
  lower            = true
  number           = true
}

resource "aws_secretsmanager_secret" "postgres_secret" {
  name        = "${var.project_name}-${var.environment}/postgres/credentials"
  description = "Master credentials for the production PostgreSQL database"
}

resource "aws_secretsmanager_secret_version" "postgres_secret_val" {
  secret_id     = aws_secretsmanager_secret.postgres_secret.id
  secret_string = jsonencode({
    engine   = "postgres"
    username = "dbadmin"
    password = random_password.db_password.result
    host     = aws_db_instance.explicit_postgres.address
    port     = 5432
    dbname   = aws_db_instance.explicit_postgres.db_name
  })
}