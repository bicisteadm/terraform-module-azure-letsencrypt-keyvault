# Azure Let's Encrypt Key Vault Terraform Module

Terraform module for automated Let's Encrypt certificate issuance and renewal with direct upload to Azure Key Vault. Designed for Azure services that don't support managed certificates natively, such as Application Gateway.

This module deploys the infrastructure for [bicisteadm/azure-letsencrypt-keyvault](https://github.com/bicisteadm/azure-letsencrypt-keyvault) containers on Azure Container Apps, handling HTTP-01 challenges and certificate lifecycle management automatically. Certificates are issued via Let's Encrypt ACME protocol and stored in your Key Vault, ready for consumption by Azure services.

## Features

- 🔐 Automated Let's Encrypt certificate issuance and renewal
- 🗄️ Direct certificate upload to Azure Key Vault
- 🌐 HTTP-01 challenge handling via Azure Container Apps

## What This Module Creates

- **Resource Group** - Dedicated to ACME automation workload
- **Storage Account** - With three Azure File shares:
  - ACME state persistence
  - HTTP-01 webroot
  - Application logs
- **Container Apps Environment** - Optionally connected to your subnet and Log Analytics workspace
- **Container App** - Publicly accessible serving app for HTTP-01 challenges
- **Container Apps Job** - On-demand certificate renewal job with managed identity

## Usage

### Basic Example

```hcl
module "acme_kv" {
  source  = "bicisteadm/letsencrypt-keyvault/azurerm"
  version = "~> 1.0"

  location       = "westeurope"
  name_prefix    = "myapp"
  domains        = ["example.com", "www.example.com"]
  acme_email     = "ops@example.com"
  pfx_password   = var.pfx_password
  key_vault_name = "myapp-shared-kv"

  tags = {
    environment = "production"
    workload    = "certificates"
  }
}
```

### Advanced Example with Custom Networking

```hcl
module "acme_kv" {
  source  = "bicisteadm/letsencrypt-keyvault/azurerm"
  version = "~> 1.0"

  location            = "westeurope"
  name_prefix         = "myapp"
  resource_group_name = "myapp-certificates-rg"
  
  domains              = ["example.com", "*.example.com"]
  acme_email           = "ops@example.com"
  acme_environment     = "prod"
  pfx_password         = var.pfx_password
  key_vault_name       = "myapp-kv"
  
  # Custom networking
  container_apps_subnet_id       = azurerm_subnet.container_apps.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.main.id
  
  # Custom container images
  serving_image = "docker.io/bicisteadm/acme-kv-serving:1.0.0"
  renewer_image = "docker.io/bicisteadm/acme-kv-renewer:1.0.0"

  tags = {
    environment = "production"
  }
}
```

### Triggering Certificate Renewal

Manually trigger the renewal job using Azure CLI:

```bash
az containerapp job start \
  --name $(echo ${module.acme_kv.renewer_job_id} | awk -F/ '{print $NF}') \
  --resource-group ${module.acme_kv.resource_group_name}
```

Or schedule it with Azure Logic Apps, Event Grid, or cron jobs.

## Requirements

| Name | Version |
|------|------|
| terraform | >= 1.6 |
| azurerm | >= 3.115.0 |
| random | >= 3.6.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| location | Azure region where all resources will be created | `string` | n/a | yes |
| domains | List of domains that should receive Let's Encrypt certificates | `list(string)` | n/a | yes |
| acme_email | Contact email passed to Let's Encrypt during ACME registration | `string` | n/a | yes |
| pfx_password | Password that protects generated PFX bundles before upload to Key Vault | `string` | n/a | yes |
| key_vault_name | Name of the Key Vault where certificates will be uploaded | `string` | n/a | yes |
| name_prefix | Project prefix applied to resource names | `string` | `"acmekv"` | no |
| resource_group_name | Optional custom name for the resource group. If not provided, will be generated | `string` | `null` | no |
| acme_environment | ACME environment selector: prod or staging | `string` | `"staging"` | no |
| log_to_file | When true, ACME containers persist logs to Azure File share | `bool` | `true` | no |
| serving_image | Container image that exposes the ACME HTTP-01 challenge endpoint | `string` | `"docker.io/bicisteadm/acme-kv-serving:0.0.4-dev"` | no |
| renewer_image | Container image responsible for issuing and renewing certificates | `string` | `"docker.io/bicisteadm/acme-kv-renewer:0.0.4-dev"` | no |
| renewal_schedule | Cron expression for automatic certificate renewal (null = manual only) | `string` | `"0 2 1 * *"` | no |
| storage_share_quota_state | Storage quota in GB for acme.sh state share | `number` | `1` | no |
| storage_share_quota_webroot | Storage quota in GB for webroot share (HTTP-01 challenges) | `number` | `1` | no |
| storage_share_quota_logs | Storage quota in GB for logs share | `number` | `1` | no |
| container_apps_subnet_id | Optional resource ID of a delegated subnet for Container Apps Environment | `string` | `null` | no |
| log_analytics_workspace_id | Optional Log Analytics workspace ID for Container Apps diagnostics | `string` | `null` | no |
| tags | Additional tags applied to every resource created by the module | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| resource_group_name | Name of the resource group hosting the ACME workload |
| container_app_environment_id | Resource ID of the Container Apps Environment |
| serving_app_fqdn | Public FQDN that exposes the ACME HTTP-01 webroot |
| renewer_job_id | Resource ID of the certificate renewal Container Apps Job |

## Important Notes

### Key Vault Permissions

The renewer job uses a **system-assigned managed identity**. You must grant this identity permissions to your Key Vault:

```hcl
resource "azurerm_key_vault_access_policy" "renewer" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_container_app_job.renewer_job.identity[0].principal_id

  certificate_permissions = [
    "Get",
    "List",
    "Import",
    "Update"
  ]
}
```

Or use RBAC:

```bash
az role assignment create \
  --role "Key Vault Certificates Officer" \
  --assignee <renewer-job-principal-id> \
  --scope /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<kv-name>
```

### Networking

- If you don't provide `container_apps_subnet_id`, Azure provisions the environment with public networking
- The serving app must be publicly accessible for HTTP-01 challenges to work
- If using a custom subnet, ensure it's delegated to `Microsoft.App/environments`

### HTTP-01 Challenge Configuration

**Critical**: For Let's Encrypt to successfully validate domain ownership, you must route `/.well-known/acme-challenge/*` requests from your domains to the serving app's FQDN.

#### Application Gateway Example

```hcl
resource "azurerm_application_gateway" "main" {
  # ... other configuration ...

  backend_address_pool {
    name  = "acme-challenge-pool"
    fqdns = [module.acme_kv.serving_app_fqdn]
  }

  backend_http_settings {
    name                  = "acme-challenge-http"
    port                  = 80
    protocol              = "Http"
    cookie_based_affinity = "Disabled"
    pick_host_name_from_backend_address = true
  }

  url_path_map {
    name                               = "acme-challenge-routing"
    default_backend_address_pool_name  = "your-default-pool"
    default_backend_http_settings_name = "your-default-settings"

    path_rule {
      name                       = "acme-challenge"
      paths                      = ["/.well-known/acme-challenge/*"]
      backend_address_pool_name  = "acme-challenge-pool"
      backend_http_settings_name = "acme-challenge-http"
    }
  }
}
```

## License

MIT

## Contributing

Contributions are welcome! Please open an issue or pull request on [GitHub](https://github.com/bicisteadm/azure-letsencrypt-keyvault-terraform).
