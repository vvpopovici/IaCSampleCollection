output "okMessage" {
  value = "All is fine!!!"
}

output "solution_name" {
  value = var.solution_name
}

output "customer_name" {
  value = var.customer_name
}

output "env_name" {
  value = var.env_name
}

output "suffix" {
  value = local.suffix
}

output "resource_group_name" {
  value = data.azurerm_resource_group.this.name
}

output "location" {
  value = data.azurerm_resource_group.this.location
}

output "tenant_id" {
  value = data.azurerm_client_config.azurecontext.tenant_id
}

output "keyvault_name" {
  value = azurerm_key_vault.this.name
}

output "container_registry_name" {
  value = azurerm_container_registry.this.name
}

output "container_registry_id" {
  value = azurerm_container_registry.this.id
}

output "container_registry_login_server" {
  value = azurerm_container_registry.this.login_server
}

output "storageaccount_id" {
  value = azurerm_storage_account.this.id
}

output "storageaccount_name" {
  value = azurerm_storage_account.this.name
}

output "storagecontainer_name" {
  value = azurerm_storage_container.this.name
}

output "comma_separated_allowed_ips" {
  value = join(",", local.aks_api_authorized_ip_ranges)
}

output "servicebus_name" {
  value = azurerm_servicebus_namespace.this.name
}

output "servicebus_requests_queue_name" {
  value = azurerm_servicebus_queue.sb_requests.name
}

output "servicebus_response_queue_name" {
  value = azurerm_servicebus_queue.sb_response.name
}

output "aks_id" {
  value = azurerm_kubernetes_cluster.this.id
}

output "aks_name" {
  value = azurerm_kubernetes_cluster.this.name
}

output "aks_fqdn" {
  value = azurerm_kubernetes_cluster.this.fqdn
}

output "aks_mc_resourcegroup" {
  value = azurerm_kubernetes_cluster.this.node_resource_group
}

output "aks_identity_id" {
  value = azurerm_kubernetes_cluster.this.identity[0].principal_id
}

output "aks_keyvault_identity_client_id" {
  value = azurerm_kubernetes_cluster.this.key_vault_secrets_provider[0].secret_identity[0].client_id
}

output "aks_pool_identity_client_id" {
  value = azurerm_kubernetes_cluster.this.kubelet_identity[0].client_id
}

output "aks_pool_identity_resource_id" {
  value = azurerm_kubernetes_cluster.this.kubelet_identity[0].user_assigned_identity_id
}

output "aks_ingress_domain_label" {
  value = azurerm_public_ip.this.domain_name_label
}

output "aks_ingress_public_ip" {
  value = azurerm_public_ip.this.ip_address
}

output "aks_ingress_fqdn" {
  value = azurerm_public_ip.this.fqdn
}

output "aks" { # terraform output -json aks
  value     = azurerm_kubernetes_cluster.this
  sensitive = true
}
