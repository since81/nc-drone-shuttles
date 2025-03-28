data "http" "database_ca_cert" {
  url = "https://dl.cacerts.digicert.com/DigiCertGlobalRootCA.crt.pem"
}

resource "azurerm_key_vault_secret" "db" {
  for_each = {
    "database-host" : azurerm_mysql_flexible_server.this.fqdn,
    "database-name" : azurerm_mysql_flexible_database.this["drone"].name
    "database-ca-cert" : data.http.database_ca_cert.response_body
  }

  key_vault_id = azurerm_key_vault.this.id
  name         = each.key
  value        = each.value

  depends_on = [
    module.kv_admin
  ]

  tags = local.tags
}
