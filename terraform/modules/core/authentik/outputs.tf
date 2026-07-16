

output "infra_admins_group_id" {
  description = "Authentik group ID for infra-admins — used for onboarding DB admin users"
  value       = authentik_group.admins.id
}

output "infra_developers_group_id" {
  description = "Authentik group ID for infra-developers"
  value       = authentik_group.developers.id
}

output "terraform_token" {
  description = "Automation token for Terraform-managed Authentik operations"
  value       = authentik_token.terraform.key
  sensitive   = true
}
