locals {
  tags = merge({
    component = "acme-kv"
  }, var.tags)

  domains_csv = join(",", var.domains)

  storage_account_name = lower(substr(replace("${var.name_prefix}st", "/[^a-z0-9]/", ""), 0, 24))
  resource_group_name  = var.resource_group_name != null ? var.resource_group_name : "${var.name_prefix}-rg"
  cae_name             = "${var.name_prefix}-cae"
  serving_app_name     = "${var.name_prefix}-serving-ca"
  renewer_job_name     = "${var.name_prefix}-renewer-ca"
}

resource "azurerm_resource_group" "acme_rg" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.tags
}

resource "azurerm_storage_account" "acme_storage" {
  name                            = local.storage_account_name
  resource_group_name             = azurerm_resource_group.acme_rg.name
  location                        = azurerm_resource_group.acme_rg.location
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = true
  tags                            = local.tags
}

resource "azurerm_storage_share" "state_share" {
  name               = "acme-storage"
  storage_account_id = azurerm_storage_account.acme_storage.id
  quota              = var.storage_share_quota_state
}

resource "azurerm_storage_share" "webroot_share" {
  name               = "acme-webroot"
  storage_account_id = azurerm_storage_account.acme_storage.id
  quota              = var.storage_share_quota_webroot
}

resource "azurerm_storage_share" "logs_share" {
  name               = "acme-logs"
  storage_account_id = azurerm_storage_account.acme_storage.id
  quota              = var.storage_share_quota_logs
}

resource "azurerm_container_app_environment" "acme_env" {
  name                       = local.cae_name
  location                   = azurerm_resource_group.acme_rg.location
  resource_group_name        = azurerm_resource_group.acme_rg.name
  infrastructure_subnet_id   = var.container_apps_subnet_id
  logs_destination           = var.log_analytics_workspace_id == null ? "azure-monitor" : "log-analytics"
  log_analytics_workspace_id = var.log_analytics_workspace_id
  tags                       = local.tags
}

resource "azurerm_container_app_environment_storage" "state_storage" {
  name                         = azurerm_storage_share.state_share.name
  container_app_environment_id = azurerm_container_app_environment.acme_env.id
  account_name                 = azurerm_storage_account.acme_storage.name
  share_name                   = azurerm_storage_share.state_share.name
  access_key                   = azurerm_storage_account.acme_storage.primary_access_key
  access_mode                  = "ReadWrite"
}

resource "azurerm_container_app_environment_storage" "webroot_storage" {
  name                         = azurerm_storage_share.webroot_share.name
  container_app_environment_id = azurerm_container_app_environment.acme_env.id
  account_name                 = azurerm_storage_account.acme_storage.name
  share_name                   = azurerm_storage_share.webroot_share.name
  access_key                   = azurerm_storage_account.acme_storage.primary_access_key
  access_mode                  = "ReadWrite"
}

resource "azurerm_container_app_environment_storage" "logs_storage" {
  name                         = azurerm_storage_share.logs_share.name
  container_app_environment_id = azurerm_container_app_environment.acme_env.id
  account_name                 = azurerm_storage_account.acme_storage.name
  share_name                   = azurerm_storage_share.logs_share.name
  access_key                   = azurerm_storage_account.acme_storage.primary_access_key
  access_mode                  = "ReadWrite"
}

resource "azurerm_container_app" "serving_app" {
  name                         = local.serving_app_name
  resource_group_name          = azurerm_resource_group.acme_rg.name
  container_app_environment_id = azurerm_container_app_environment.acme_env.id
  revision_mode                = "Single"
  tags                         = local.tags

  template {
    min_replicas = 0
    max_replicas = 1

    volume {
      name         = "acme-webroot-volume"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.webroot_storage.name
    }

    container {
      name   = "serving"
      image  = var.serving_image
      cpu    = 0.25
      memory = "0.5Gi"

      volume_mounts {
        name = "acme-webroot-volume"
        path = "/webroot"
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 8080
    transport        = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  depends_on = [azurerm_container_app_environment_storage.webroot_storage]
}

resource "azurerm_container_app_job" "renewer_job" {
  name                         = local.renewer_job_name
  resource_group_name          = azurerm_resource_group.acme_rg.name
  location                     = azurerm_resource_group.acme_rg.location
  container_app_environment_id = azurerm_container_app_environment.acme_env.id
  replica_timeout_in_seconds   = 1800
  tags                         = local.tags

  dynamic "schedule_trigger_config" {
    for_each = var.renewal_schedule != null ? [1] : []
    content {
      cron_expression          = var.renewal_schedule
      parallelism              = 1
      replica_completion_count = 1
    }
  }

  dynamic "manual_trigger_config" {
    for_each = var.renewal_schedule == null ? [1] : []
    content {
      parallelism              = 1
      replica_completion_count = 1
    }
  }

  identity {
    type = "SystemAssigned"
  }

  secret {
    name  = "pfx-pass"
    value = var.pfx_password
  }

  template {
    volume {
      name         = "acme-state-volume"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.state_storage.name
    }

    volume {
      name         = "acme-webroot-volume"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.webroot_storage.name
    }

    volume {
      name         = "acme-logs-volume"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.logs_storage.name
    }

    container {
      name   = "renewer"
      image  = var.renewer_image
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "DOMAINS"
        value = local.domains_csv
      }

      env {
        name  = "ACME_EMAIL"
        value = var.acme_email
      }

      env {
        name  = "ACME_ENV"
        value = lower(var.acme_environment)
      }

      env {
        name  = "WEBROOT_PATH"
        value = "/webroot"
      }

      env {
        name  = "LOG_DIR"
        value = "/logs"
      }

      env {
        name  = "LOG_TO_FILE"
        value = var.log_to_file ? "true" : "false"
      }

      env {
        name  = "KEYVAULT_NAME"
        value = var.key_vault_name
      }

      env {
        name        = "PFX_PASS"
        secret_name = "pfx-pass"
      }

      volume_mounts {
        name = "acme-state-volume"
        path = "/acme.sh"
      }

      volume_mounts {
        name = "acme-webroot-volume"
        path = "/webroot"
      }

      volume_mounts {
        name = "acme-logs-volume"
        path = "/logs"
      }
    }
  }

  depends_on = [
    azurerm_container_app_environment_storage.state_storage,
    azurerm_container_app_environment_storage.webroot_storage,
    azurerm_container_app_environment_storage.logs_storage
  ]
}
