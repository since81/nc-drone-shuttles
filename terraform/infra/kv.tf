resource "azurerm_key_vault" "this" {
  name                            = "${local.resource_name_prefix}-kv"
  location                        = azurerm_resource_group.this.location
  resource_group_name             = azurerm_resource_group.this.name
  tenant_id                       = data.azurerm_client_config.current.tenant_id
  sku_name                        = var.env.key_vault.sku_name
  purge_protection_enabled        = true
  enabled_for_disk_encryption     = true
  enabled_for_deployment          = true
  enabled_for_template_deployment = true
  enable_rbac_authorization       = true
  soft_delete_retention_days      = 7
  public_network_access_enabled   = var.env.key_vault.public_network_access_enabled

  network_acls {
    bypass         = "AzureServices"
    default_action = "Allow"
    ip_rules       = []
    virtual_network_subnet_ids = [
      azurerm_subnet.this["k8s"].id,
      azurerm_subnet.this["app_gateway"].id
    ]
  }

  tags = local.tags
}

module "kv_admin" {
  source = "../../modules/azure/authorization/role-assignment"

  object_id            = data.azurerm_client_config.current.object_id
  role_definition_name = "Key Vault Administrator"
  resource_id          = azurerm_key_vault.this.id
}

resource "random_password" "this" {
  for_each = {
    for k, v in try(var.env.key_vault.secrets, {}) : k => v
    if try(v.value, "") == ""
  }

  length  = try(each.value.length, 32)
  lower   = try(each.value.lower, true)
  upper   = try(each.value.upper, true)
  numeric = try(each.value.numeric, true)
  special = try(each.value.special, false)
}

resource "azurerm_key_vault_secret" "this" {
  for_each = try(var.env.key_vault.secrets, {})

  key_vault_id = azurerm_key_vault.this.id
  name         = each.key
  value        = try(each.value.value, "") != "" ? each.value.value : random_password.this[each.key].result

  depends_on = [
    azurerm_key_vault.this,
    module.kv_admin,
    random_password.this
  ]

  tags = local.tags
}

resource "azurerm_key_vault_certificate" "drones_shuttles" {
  name         = "drones-shuttles"
  key_vault_id = azurerm_key_vault.this.id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_size   = 4096
      key_type   = "RSA"
      reuse_key  = true
    }

    lifetime_action {
      action {
        action_type = "AutoRenew"
      }

      trigger {
        days_before_expiry = 30
      }
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      # Server Authentication = 1.3.6.1.5.5.7.3.1
      # Client Authentication = 1.3.6.1.5.5.7.3.2
      extended_key_usage = ["1.3.6.1.5.5.7.3.1"]

      key_usage = [
        "cRLSign",
        "dataEncipherment",
        "digitalSignature",
        "keyAgreement",
        "keyCertSign",
        "keyEncipherment",
      ]

      subject_alternative_names {
        dns_names = ["*.drones-shuttles.org"]
      }

      subject            = "CN=drones-shuttles.org"
      validity_in_months = 12
    }
  }

  depends_on = [
    azurerm_key_vault.this,
    module.kv_admin
  ]

  tags = local.tags
}
