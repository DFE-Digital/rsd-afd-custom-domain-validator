module "azurerm_key_vault" {
  source = "github.com/DFE-Digital/terraform-azurerm-key-vault-tfvars?ref=v0.4.2"

  environment                             = local.environment
  project_name                            = "afdcdv"
  existing_resource_group                 = azurerm_resource_group.default.name
  azure_location                          = local.region
  key_vault_access_use_rbac_authorization = true
  key_vault_access_users                  = []
  key_vault_access_ipv4                   = local.key_vault_access_ipv4
  tfvars_filename                         = local.tfvars_filename
  enable_diagnostic_setting               = false
  enable_diagnostic_storage_account       = false
  tags                                    = local.tags
}
