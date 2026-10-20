# Postgres 17 (pgvector) and Valkey, both private, encrypted, and reachable only from the nodes.
# This is a demo of fictional data: no final snapshot or backups, and seeds rebuild it on every `make up`.

resource "random_password" "db" {
  length  = 32
  special = false
}

resource "random_password" "cache" {
  length  = 40
  special = false
}

resource "aws_security_group" "data" {
  name        = "cubby-data"
  description = "Postgres and Valkey from the nodes only"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "data_from_nodes" {
  for_each                     = { postgres = 5432, valkey = 6379 }
  security_group_id            = aws_security_group.data.id
  referenced_security_group_id = module.eks.node_security_group_id
  from_port                    = each.value
  to_port                      = each.value
  ip_protocol                  = "tcp"
  description                  = "${each.key} from nodes"
}

resource "aws_db_subnet_group" "cubby" {
  name       = "cubby"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_db_instance" "cubby" {
  identifier                 = "cubby"
  engine                     = "postgres"
  engine_version             = "17"
  instance_class             = "db.t4g.micro"
  allocated_storage          = 20
  storage_type               = "gp3"
  storage_encrypted          = true
  db_name                    = "cubby"
  username                   = "cubby"
  password                   = random_password.db.result
  db_subnet_group_name       = aws_db_subnet_group.cubby.name
  vpc_security_group_ids     = [aws_security_group.data.id]
  publicly_accessible        = false
  backup_retention_period    = 0
  skip_final_snapshot        = true
  deletion_protection        = false
  apply_immediately          = true
  auto_minor_version_upgrade = true
}

resource "aws_elasticache_subnet_group" "cubby" {
  name       = "cubby"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_elasticache_replication_group" "cubby" {
  replication_group_id       = "cubby"
  description                = "Cubby Sidekiq, cron, and rate limits"
  engine                     = "valkey"
  engine_version             = "8.2"
  node_type                  = "cache.t4g.micro"
  num_cache_clusters         = 1
  port                       = 6379
  subnet_group_name          = aws_elasticache_subnet_group.cubby.name
  security_group_ids         = [aws_security_group.data.id]
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.cache.result
  apply_immediately          = true
}
