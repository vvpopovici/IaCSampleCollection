#region Locals
locals {
  suffix           = "${var.solution_name}-${var.customer_name}-${var.env_name}"
  suffix_no_dashes = "${var.solution_name}${var.customer_name}${var.env_name}"

  allowed_ips_vvp_vpn = jsondecode(file("${path.module}/allowed-ips-vvp-addresses-short.json"))
  allowed_ips_extra      = jsondecode(file("${path.module}/allowed-ips-extra.json"))
  allowed_ips = setunion( # Keep this list as short as possible. Note that Service Bus Firewall accepts maximum 128 IPs.
    [for item in local.allowed_ips_vvp_vpn : item if length(trim(item.ip, " \t\n\r")) > 0],
    [for item in local.allowed_ips_extra : item if length(trim(item.ip, " \t\n\r")) > 0]
  )

  storageaccount_ip_rules = setunion( # /0-30 only accepted
    [for item in local.allowed_ips : item.ip if contains(["31", "32"], item.subnet)],
    [for item in local.allowed_ips : "${item.ip}/${item.subnet}" if !contains(["31", "32"], item.subnet)]
  )

  servicebus_ip_rules = setunion(
    [for item in local.allowed_ips : item.ip if contains(["32"], item.subnet)],
    [for item in local.allowed_ips : "${item.ip}/${item.subnet}" if !contains(["31", "32"], item.subnet)]
  )

  keyvault_ip_rules = setunion(
    [for item in local.allowed_ips : "${item.ip}/${item.subnet}"]
  )

  aks_api_authorized_ip_ranges = setunion(
    [for item in local.allowed_ips : "${item.ip}/${item.subnet}"]
  )

  peer_to_buildagents_network = length(var.buildagents_resource_group_name) > 0 && length(var.buildagents_virtual_network_name) > 0 && length(var.buildagents_subnet_name) > 0 ? true : false
}
#endregion

###################################################
#region Existent Resources
###################################################

data "azurerm_client_config" "azurecontext" {}

data "azurerm_resource_group" "this" {
  name = length(trim(var.resource_group_name, " \t\n\r")) == 0 ? "rg-${local.suffix}" : var.resource_group_name
}

provider "azurerm" {
  alias = "buildagents"
  features {}
  subscription_id = length(var.buildagents_subscription_id) > 0 ? var.buildagents_subscription_id : data.azurerm_client_config.azurecontext.subscription_id
}

data "azurerm_virtual_network" "buildagents" {
  count               = local.peer_to_buildagents_network ? 1 : 0
  provider            = azurerm.buildagents
  name                = var.buildagents_virtual_network_name
  resource_group_name = var.buildagents_resource_group_name
}

data "azurerm_subnet" "buildagents" {
  count                = local.peer_to_buildagents_network ? 1 : 0
  provider             = azurerm.buildagents
  name                 = var.buildagents_subnet_name
  virtual_network_name = data.azurerm_virtual_network.buildagents[0].name
  resource_group_name  = var.buildagents_resource_group_name
}

#endregion

###################################################
#region Independent Resources
###################################################

resource "azurerm_public_ip" "this" {
  name                = "pip-${local.suffix}"
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = local.suffix
  tags                = var.global_tags
}

resource "azurerm_virtual_network" "this" {
  name                = "vnt-${local.suffix}"
  location            = data.azurerm_resource_group.this.location
  address_space       = ["10.224.0.0/12"]
  resource_group_name = data.azurerm_resource_group.this.name
  # private_endpoint_vnet_policies = "Disabled"
  tags = var.global_tags
}

resource "azurerm_subnet" "aks" {
  name                 = "aks-subnet"
  resource_group_name  = data.azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.224.0.0/16"]
  service_endpoints    = ["Microsoft.Storage", "Microsoft.ServiceBus", "Microsoft.ContainerRegistry", "Microsoft.KeyVault"]
}

resource "azurerm_subnet" "endpoints" {
  name                 = "endpoints-subnet"
  resource_group_name  = data.azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.225.1.0/24"]
  service_endpoints    = ["Microsoft.Storage", "Microsoft.ServiceBus", "Microsoft.ContainerRegistry", "Microsoft.KeyVault"]
}

# Peering to build agents VNet (if provided)
resource "azurerm_virtual_network_peering" "to_buildagents" {
  count                     = local.peer_to_buildagents_network ? 1 : 0
  name                      = "peer-to-${data.azurerm_virtual_network.buildagents[0].name}"
  resource_group_name       = data.azurerm_resource_group.this.name
  virtual_network_name      = azurerm_virtual_network.this.name
  remote_virtual_network_id = data.azurerm_virtual_network.buildagents[0].id
  # allow_forwarded_traffic = true
  # allow_gateway_transit = true
  # allow_virtual_network_access = true
  # use_remote_gateways = true
}

resource "azurerm_virtual_network_peering" "from_buildagents" {
  count                     = local.peer_to_buildagents_network ? 1 : 0
  name                      = "peer-to-${azurerm_virtual_network.this.name}"
  resource_group_name       = data.azurerm_virtual_network.buildagents[0].resource_group_name
  virtual_network_name      = data.azurerm_virtual_network.buildagents[0].name
  remote_virtual_network_id = azurerm_virtual_network.this.id
}

resource "azurerm_key_vault" "this" {
  # count                    = var.container_registry_authorization_rbac && var.storage_authorization_rbac && var.servicebus_authorization_rbac ? 0 : 1
  name                            = "kv-${local.suffix}"
  resource_group_name             = data.azurerm_resource_group.this.name
  location                        = data.azurerm_resource_group.this.location
  sku_name                        = "standard"
  tenant_id                       = data.azurerm_client_config.azurecontext.tenant_id
  enable_rbac_authorization       = true
  enabled_for_deployment          = true
  enabled_for_template_deployment = true
  # soft_delete_retention_days    = 7 # can not be changed after creation
  purge_protection_enabled      = false
  tags                          = var.global_tags
  public_network_access_enabled = true
  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = setunion(local.keyvault_ip_rules, [azurerm_public_ip.this.ip_address])
    virtual_network_subnet_ids = setunion(
      [azurerm_subnet.aks.id, azurerm_subnet.endpoints.id],
      local.peer_to_buildagents_network ? [data.azurerm_subnet.buildagents[0].id] : []
    )
  }
}
#endregion

###################################################
#region Container Registry
###################################################

resource "azurerm_container_registry" "this" {
  name                   = substr("acr${local.suffix_no_dashes}", 0, 50)
  resource_group_name    = data.azurerm_resource_group.this.name
  location               = data.azurerm_resource_group.this.location
  sku                    = var.container_registry_sku
  admin_enabled          = !var.container_registry_authorization_rbac
  anonymous_pull_enabled = !var.container_registry_authorization_rbac
  tags                   = var.global_tags
}

resource "azurerm_key_vault_secret" "acr_username" {
  count           = !var.container_registry_authorization_rbac ? 1 : 0
  name            = "${azurerm_container_registry.this.name}-username"
  key_vault_id    = azurerm_key_vault.this.id
  value           = azurerm_container_registry.this.admin_username
  expiration_date = "2030-01-01T00:00:00Z" # Set a long expiration date
}

resource "azurerm_key_vault_secret" "acr_password" {
  count           = !var.container_registry_authorization_rbac ? 1 : 0
  name            = "${azurerm_container_registry.this.name}-password"
  key_vault_id    = azurerm_key_vault.this.id
  value           = azurerm_container_registry.this.admin_password
  expiration_date = "2030-01-01T00:00:00Z" # Set a long expiration date
}
#endregion

###################################################
#region Storage Account
###################################################

resource "azurerm_storage_account" "this" {
  name                     = substr("sa${local.suffix_no_dashes}", 0, 24)
  resource_group_name      = data.azurerm_resource_group.this.name
  location                 = data.azurerm_resource_group.this.location
  account_tier             = "Standard"
  account_kind             = "StorageV2"
  account_replication_type = "LRS"
  tags                     = var.global_tags

  is_hns_enabled             = true
  large_file_share_enabled   = true
  min_tls_version            = "TLS1_2"
  https_traffic_only_enabled = true

  local_user_enabled              = !var.storage_authorization_rbac
  default_to_oauth_authentication = var.storage_authorization_rbac
  shared_access_key_enabled       = true
  allow_nested_items_to_be_public = true # "Allow Blob anonymous access" in the UI

  blob_properties {
    last_access_time_enabled = true
    container_delete_retention_policy {
      days = 1
    }
    delete_retention_policy {
      days                     = 1
      permanent_delete_enabled = true
    }
  }
  public_network_access_enabled = true # This allows ip_rules to have effect
  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
    ip_rules       = setunion(local.storageaccount_ip_rules, [azurerm_public_ip.this.ip_address])
    virtual_network_subnet_ids = setunion(
      [azurerm_subnet.aks.id, azurerm_subnet.endpoints.id],
      local.peer_to_buildagents_network ? [data.azurerm_subnet.buildagents[0].id] : []
    )
  }
}

resource "azurerm_storage_container" "this" {
  name                  = var.storage_container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_key_vault_secret" "sa_connstr" {
  count           = !var.storage_authorization_rbac ? 1 : 0
  name            = "${azurerm_storage_account.this.name}-connstr"
  key_vault_id    = azurerm_key_vault.this.id
  value           = azurerm_storage_account.this.primary_connection_string
  expiration_date = "2030-01-01T00:00:00Z" # Set a long expiration date
}

resource "azurerm_key_vault_secret" "sa_key" {
  count           = !var.storage_authorization_rbac ? 1 : 0
  name            = "${azurerm_storage_account.this.name}-key"
  key_vault_id    = azurerm_key_vault.this.id
  value           = azurerm_storage_account.this.primary_access_key
  expiration_date = "2030-01-01T00:00:00Z" # Set a long expiration date
}
#endregion

###################################################
#region Service Bus
###################################################
resource "azurerm_servicebus_namespace" "this" {
  name                = "sb-${local.suffix}"
  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location
  sku                 = "Basic"
  local_auth_enabled  = !var.servicebus_authorization_rbac
  minimum_tls_version = "1.2"
  # capacity                            = 0
  # premium_messaging_partitions        = 0
  public_network_access_enabled = true

  ### Only Premium plan allows Private Networking.
  ### Configuration fails with "InvalidSkuForNetworkRuleSet: Sku 'Basic/Standard' does not support network rule set".
  network_rule_set {
    #   default_action = "Allow"
    #   public_network_access_enabled = true
    #   trusted_services_allowed      = true
    #   ip_rules = setunion(
    #     local.servicebus_ip_rules,
    #     [azurerm_public_ip.this.ip_address],
    #     azurerm_subnet.aks.address_prefixes,
    #     azurerm_subnet.endpoints.address_prefixes
    #   )
    #   network_rules {
    #     subnet_id = azurerm_subnet.endpoints.id
    #   }
  }
  tags = var.global_tags
}

resource "azurerm_servicebus_queue" "sb_requests" {
  namespace_id          = azurerm_servicebus_namespace.this.id
  name                  = "sbq-${local.suffix}-reqs"
  max_size_in_megabytes = 1024
  lock_duration         = "PT5M"
}

resource "azurerm_servicebus_queue" "sb_response" {
  namespace_id          = azurerm_servicebus_namespace.this.id
  name                  = "sbq-${local.suffix}-resp"
  max_size_in_megabytes = 1024
  lock_duration         = "PT5M"
}

resource "azurerm_key_vault_secret" "sb_connstr" {
  count           = !var.servicebus_authorization_rbac ? 1 : 0
  name            = "${azurerm_servicebus_namespace.this.name}-connstr"
  key_vault_id    = azurerm_key_vault.this.id
  value           = azurerm_servicebus_namespace.this.default_primary_connection_string
  expiration_date = "2030-01-01T00:00:00Z" # Set a long expiration date
}

resource "azurerm_key_vault_secret" "sb_key" {
  count           = !var.servicebus_authorization_rbac ? 1 : 0
  name            = "${azurerm_servicebus_namespace.this.name}-key"
  key_vault_id    = azurerm_key_vault.this.id
  value           = azurerm_servicebus_namespace.this.default_primary_key
  expiration_date = "2030-01-01T00:00:00Z" # Set a long expiration date
}
#endregion

###################################################
#region Kubernetes Cluster
###################################################

resource "azurerm_kubernetes_cluster" "this" {
  name                         = "aks-${local.suffix}"
  resource_group_name          = data.azurerm_resource_group.this.name
  location                     = data.azurerm_resource_group.this.location
  kubernetes_version           = "1.33.2"
  sku_tier                     = "Free" # Valid values: Free, Standard
  image_cleaner_enabled        = true
  image_cleaner_interval_hours = 168
  tags                         = var.global_tags

  custom_ca_trust_certificates_base64 = []

  ### Networking
  dns_prefix = "aks-${local.suffix}"
  network_profile {
    network_plugin = "azure"
    load_balancer_profile {
      outbound_ip_address_ids = [azurerm_public_ip.this.id]
    }
  }
  api_server_access_profile {
    authorized_ip_ranges = setunion(
      local.aks_api_authorized_ip_ranges,
      ["${azurerm_public_ip.this.ip_address}/32"]
    )
  }

  ### Identities and roles
  identity {
    type         = "SystemAssigned"
    identity_ids = []
  }
  oidc_issuer_enabled               = true
  local_account_disabled            = true
  role_based_access_control_enabled = true
  workload_identity_enabled         = true
  azure_active_directory_role_based_access_control {
    azure_rbac_enabled     = true
    admin_group_object_ids = [var.aks_admin_group_object_id]
    tenant_id              = data.azurerm_client_config.azurecontext.tenant_id
  }
  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  default_node_pool {
    name                        = "systempool"
    temporary_name_for_rotation = "systempooltm" # 1-12 chars, must be specified when updating vm_size and some other properties
    tags                        = var.global_tags
    node_labels = {
      mode = "system"
      type = "system"
    }

    vm_size                = "Standard_DS2_v2" # vCPU=2, Memory=7GB
    type                   = "VirtualMachineScaleSets"
    auto_scaling_enabled   = true
    min_count              = 1
    max_count              = 2
    scale_down_mode        = "Delete"
    zones                  = ["3"]
    node_public_ip_enabled = false
    vnet_subnet_id         = azurerm_subnet.aks.id

    upgrade_settings {
      drain_timeout_in_minutes      = 0
      max_surge                     = "10%"
      node_soak_duration_in_minutes = 0
    }
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "commonpool" {
  name                        = "commonpool"
  temporary_name_for_rotation = "commonpooltm"
  tags                        = var.global_tags
  kubernetes_cluster_id       = azurerm_kubernetes_cluster.this.id
  mode                        = "User"
  node_labels = {
    mode = "user"
    type = "common"
  }

  vm_size                = var.aks_commonpool.vm_size
  auto_scaling_enabled   = true
  min_count              = var.aks_commonpool.min_count
  max_count              = var.aks_commonpool.max_count
  scale_down_mode        = "Delete"
  zones                  = ["2"]
  node_public_ip_enabled = false
  vnet_subnet_id         = azurerm_subnet.aks.id

  upgrade_settings {
    drain_timeout_in_minutes      = 0
    max_surge                     = "10%"
    node_soak_duration_in_minutes = 0
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "gpupool" {
  name                        = "gpupool"
  temporary_name_for_rotation = "gpupooltemp" # 1-12 chars, must be specified when updating vm_size and some other properties
  tags                        = var.global_tags
  kubernetes_cluster_id       = azurerm_kubernetes_cluster.this.id
  mode                        = "User"
  node_labels = {
    mode = "user"
    type = "gpu"
  }

  vm_size     = var.aks_gpupool.vm_size
  os_type     = "Linux"
  node_taints = ["sku=gpu:NoSchedule"]

  auto_scaling_enabled   = true
  min_count              = var.aks_gpupool.min_count
  max_count              = var.aks_gpupool.max_count
  scale_down_mode        = "Delete"
  zones                  = ["3"]
  node_public_ip_enabled = false
  vnet_subnet_id         = azurerm_subnet.aks.id

  upgrade_settings {
    drain_timeout_in_minutes      = 0
    max_surge                     = "10%"
    node_soak_duration_in_minutes = 0
  }
}

#endregion

###################################################
#region Role Assignments
###################################################
# Find Azure built-in roles here https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles

resource "azurerm_role_assignment" "kubernetes_network" {
  description          = "Assign to ${azurerm_kubernetes_cluster.this.name} (Api) the role 'Network Contributor' over ${var.resource_group_name}"
  principal_id         = azurerm_kubernetes_cluster.this.identity[0].principal_id
  principal_type       = "ServicePrincipal"
  role_definition_name = "Network Contributor" # This is required to use the Public IP resource
  scope                = data.azurerm_resource_group.this.id
}

resource "azurerm_role_assignment" "kubernetes_acrpull" {
  count                = var.container_registry_authorization_rbac ? 1 : 0
  description          = "Assign to ${azurerm_kubernetes_cluster.this.name} (Nodes) the role 'AcrPull' over ${var.resource_group_name}"
  principal_id         = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
  principal_type       = "ServicePrincipal"
  role_definition_name = "AcrPull"
  scope                = data.azurerm_resource_group.this.id
}

resource "azurerm_role_assignment" "kubernetes_blob" {
  count                = var.storage_authorization_rbac ? 1 : 0
  description          = "Assign to ${azurerm_kubernetes_cluster.this.name} (Nodes) the role 'Storage Blob Data Contributor' over ${var.resource_group_name}"
  principal_id         = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
  principal_type       = "ServicePrincipal"
  role_definition_name = "Storage Blob Data Contributor"
  scope                = data.azurerm_resource_group.this.id
}

resource "azurerm_role_assignment" "kubernetes_servicebus" {
  count                = var.servicebus_authorization_rbac ? 1 : 0
  description          = "Assign to ${azurerm_kubernetes_cluster.this.name} (Nodes) the role 'Azure Service Bus Data Owner' over ${var.resource_group_name}"
  principal_id         = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
  principal_type       = "ServicePrincipal"
  role_definition_name = "Azure Service Bus Data Owner"
  scope                = data.azurerm_resource_group.this.id
}

resource "azurerm_role_assignment" "kubernetes_keyvault_secrets" {
  description          = "Assign to ${azurerm_kubernetes_cluster.this.name} (key_vault_secrets_provider) the role 'Key Vault Secrets User' over ${var.resource_group_name}"
  principal_id         = azurerm_kubernetes_cluster.this.key_vault_secrets_provider[0].secret_identity[0].object_id
  principal_type       = "ServicePrincipal"
  role_definition_name = "Key Vault Secrets User"
  scope                = data.azurerm_resource_group.this.id
}

resource "azurerm_role_assignment" "kubernetes_keyvault_certs" {
  description          = "Assign to ${azurerm_kubernetes_cluster.this.name} (key_vault_secrets_provider) the role 'Key Vault Certificate User' over ${var.resource_group_name}"
  principal_id         = azurerm_kubernetes_cluster.this.key_vault_secrets_provider[0].secret_identity[0].object_id
  principal_type       = "ServicePrincipal"
  role_definition_name = "Key Vault Certificate User"
  scope                = data.azurerm_resource_group.this.id
}

resource "azurerm_role_assignment" "aksadmins_keyvault_secrets" {
  description          = "Assign to ${var.aks_admin_group_name} (${var.aks_admin_group_object_id}) (Nodes) the role 'Key Vault Secrets User' over ${var.resource_group_name}"
  principal_id         = var.aks_admin_group_object_id
  principal_type       = "Group"
  role_definition_name = "Key Vault Secrets User"
  scope                = data.azurerm_resource_group.this.id
}

resource "azurerm_role_assignment" "aksadmins_keyvault_certs" {
  description          = "Assign to ${var.aks_admin_group_name} (${var.aks_admin_group_object_id}) (Nodes) the role 'Key Vault Certificate User' over ${var.resource_group_name}"
  principal_id         = var.aks_admin_group_object_id
  principal_type       = "Group"
  role_definition_name = "Key Vault Certificate User"
  scope                = data.azurerm_resource_group.this.id
}

#endregion
