resource "azurerm_postgresql_flexible_server" "this" {
  name                          = "${local.resource_name_prefix}-psql"
  location                      = azurerm_resource_group.this.location
  resource_group_name           = azurerm_resource_group.this.name
  administrator_login           = azurerm_key_vault_secret.this[var.env.databases.postgresql.administrator_login].value
  administrator_password        = azurerm_key_vault_secret.this[var.env.databases.postgresql.administrator_password].value
  delegated_subnet_id           = azurerm_subnet.this[var.env.databases.postgresql.subnet].id
  backup_retention_days         = 7
  public_network_access_enabled = var.env.databases.postgresql.public_network_access_enabled
  sku_name                      = var.env.databases.postgresql.sku_name
  storage_mb                    = 32768
  storage_tier                  = "P4"
  version                       = "16"

  lifecycle {
    ignore_changes = [
      zone
    ]
    #prevent_destroy = true
  }

  tags = local.tags
}

module "diagnostic_settings_postgres" {
  source = "../modules/azure/monitor/diagnostic-settings"

  name                       = "postgres-diagnostic-settings"
  target_resource_id         = azurerm_postgresql_flexible_server.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  logs = [
    {
      category_group = "allLogs"
    },
    {
      category_group = "audit"
    }
  ]
  metrics = [
    {
      category = "AllMetrics"
    }
  ]
}

resource "azurerm_postgresql_flexible_server_database" "this" {
  for_each = var.env.databases.postgresql.databases

  name      = each.key
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = try(each.value.charset, "utf8")
  collation = try(each.value.collation, "en_US.utf8")

  # prevent the possibility of accidental data loss
  lifecycle {
    #prevent_destroy = true
  }
}
