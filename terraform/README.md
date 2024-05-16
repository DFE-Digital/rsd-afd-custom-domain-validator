<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.1 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | >=1.13.1 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 3.51.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azapi"></a> [azapi](#provider\_azapi) | 1.13.1 |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 3.103.1 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azapi_update_resource.patch_logs](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/update_resource) | resource |
| [azurerm_container_group.default](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_group) | resource |
| [azurerm_log_analytics_workspace.default](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/log_analytics_workspace) | resource |
| [azurerm_resource_group.default](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azurerm_route_table.default](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/route_table) | resource |
| [azurerm_subnet.default](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet_route_table_association.container_apps_infra_subnet](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_route_table_association) | resource |
| [azurerm_user_assigned_identity.default](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [azurerm_virtual_network.default](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network) | resource |
| [azurerm_subscription.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/subscription) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_registry_password"></a> [registry\_password](#input\_registry\_password) | Password for authenticating to the Container Registry | `string` | n/a | yes |
| <a name="input_registry_server"></a> [registry\_server](#input\_registry\_server) | Hostname of the Container Registry | `string` | n/a | yes |
| <a name="input_registry_username"></a> [registry\_username](#input\_registry\_username) | Username for authenticating to the Container Registry | `string` | n/a | yes |

## Outputs

No outputs.
<!-- END_TF_DOCS -->