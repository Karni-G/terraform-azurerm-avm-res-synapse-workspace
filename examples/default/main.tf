## Section to provide a random Azure region for the resource group
# This allows us to randomize the region for the resource group.
module "regions" {
  source  = "Azure/regions/azurerm"
  version = ">= 0.8.0"
}

# This allows us to randomize the region for the resource group.
resource "random_integer" "region_index" {
  max = length(module.regions.regions) - 1
  min = 0
}
## End of section to provide a random Azure region for the resource group

# This allow use to randomize the name of resources
resource "random_string" "this" {
  length  = 6
  special = false
  upper   = false
}

# This ensures we have unique CAF compliant names for our resources.
module "naming" {
  source  = "Azure/naming/azurerm"
  version = ">= 0.4.1"
}

# This is required for resource modules
resource "azurerm_resource_group" "this" {
  location = module.regions.regions[random_integer.region_index.result].name
  name     = module.naming.resource_group.name_unique
}

# Get current IP address for use in KV firewall rules
data "http" "ip" {
  url = "https://api.ipify.org/"
  retry {
    attempts     = 5
    max_delay_ms = 1000
    min_delay_ms = 500
  }
}

data "azurerm_client_config" "current" {}

module "key_vault" {
  source             = "Azure/avm-res-keyvault-vault/azurerm"
  name                          = module.naming.key_vault.name_unique
  location                      = azurerm_resource_group.this.location
  enable_telemetry              = var.enable_telemetry
  resource_group_name           = azurerm_resource_group.this.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  public_network_access_enabled = true
  secrets = {
    test_secret = {
      name = "test-secret"
    }
  }
  secrets_value = {
    test_secret = "secret-value"
  }
  role_assignments = {
    deployment_user_kv_admin = {
      role_definition_id_or_name = "Key Vault Administrator"
      principal_id               = data.azurerm_client_config.current.object_id
    }
  }
  wait_for_rbac_before_secret_operations = {
    create = "60s"
  }
  network_acls = {
    bypass   = "AzureServices"
    ip_rules = ["${data.http.ip.response_body}/32"]
  }
}

module "azure_data_lake_storage"{
  source = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.2.7"
  account_replication_type      = "RAGRS"
  account_tier                  = "Standard"
  account_kind                  = "StorageV2"
  location                      = azurerm_resource_group.this.location
  name                          = module.naming.storage_account.name_unique
  https_traffic_only_enabled    = true
  resource_group_name           = azurerm_resource_group.this.name
  min_tls_version               = "TLS1_2"
  shared_access_key_enabled     = true
  is_hns_enabled                = true
  public_network_access_enabled = true
  tags = var.tags
  role_assignments = {
    role_assignment_1 = {
      role_definition_id_or_name       = "Owner"
      principal_id                     = data.azurerm_client_config.current.object_id
      skip_service_principal_aad_check = false
    },

  }

  storage_data_lake_gen2_filesystem = {
    name = var.adlsfilesystem
  }
}

# This is the module call
# Do not specify location here due to the randomization above.
# Leaving location as `null` will cause the module to use the resource group location
# with a data source.
module "test" {
  source = "../../"
  # source             = "Azure/avm-<res/ptn>-<name>/azurerm"
  # ...
  enable_telemetry    = var.enable_telemetry # see variables.tf
  name                = "TODO"               # TODO update with module.naming.<RESOURCE_TYPE>.name_unique
  resource_group_name = azurerm_resource_group.this.name
}
