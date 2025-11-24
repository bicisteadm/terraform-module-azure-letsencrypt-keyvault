output "resource_group_name" {
  description = "Resource group hosting the Container Apps workload."
  value       = azurerm_resource_group.acme_rg.name
}

output "container_app_environment_id" {
  description = "ID of the Container Apps Environment that hosts the serving app and renewer job."
  value       = azurerm_container_app_environment.acme_env.id
}

output "serving_app_fqdn" {
  description = "Externally reachable FQDN that exposes the ACME webroot."
  value       = azurerm_container_app.serving_app.latest_revision_fqdn
}

output "renewer_job_id" {
  description = "Resource ID of the Container Apps Job responsible for issuing and renewing certificates."
  value       = azurerm_container_app_job.renewer_job.id
}
