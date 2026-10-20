# Generated here, stored as SecureStrings, and read by the instance at boot (host/cloud-init.sh.tftpl),
# so no secret is in user data. The demo password is for typed sign-ins; visitors use the one-click demo.

resource "random_password" "secret_key_base" {
  length  = 64
  special = false
}

resource "random_password" "demo" {
  length  = 20
  special = false
}

resource "random_password" "db" {
  length  = 32
  special = false
}

locals {
  param_path = "/cubby/demo"
  secrets = {
    SECRET_KEY_BASE = random_password.secret_key_base.result
    DEMO_PASSWORD   = random_password.demo.result
    DB_PASSWORD     = random_password.db.result
  }
}

resource "aws_ssm_parameter" "secret" {
  for_each = local.secrets
  name     = "${local.param_path}/${each.key}"
  type     = "SecureString"
  value    = each.value
}

output "demo_password" {
  description = "Password for the demo accounts when typing a sign-in; read with terraform output -raw demo_password."
  value       = random_password.demo.result
  sensitive   = true
}
