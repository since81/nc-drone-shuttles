output "instrumentation_key" {
  value = azurerm_application_insights.this.instrumentation_key
}

output "connection_string" {
  value = azurerm_application_insights.this.connection_string
}
