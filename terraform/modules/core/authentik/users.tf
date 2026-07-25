# ------------------------------------------------------------------------------
# Enterprise Groups and Users (Role Mappings)
# ------------------------------------------------------------------------------

# 1. CORE ENTERPRISE GROUPS
resource "authentik_group" "admins" {
  name         = "infra-admins"
  is_superuser = true
}

resource "authentik_group" "developers" {
  name         = "infra-developers"
  is_superuser = false
}

# 2. SEED USERS
resource "authentik_user" "admin" {
  username = "munish-admin"
  name     = "Munish (Admin)"
  email    = "admin@${var.root_domain}"
  password = var.admin_password
  groups   = [authentik_group.admins.id]
}

resource "authentik_user" "developer" {
  username = "team-dev"
  name     = "Team Developer"
  email    = "dev@${var.root_domain}"
  password = var.dev_password
  groups   = [authentik_group.developers.id]
}

# 3. PERMANENT AUTOMATION TOKEN
resource "authentik_token" "terraform" {
  identifier   = "terraform-automation-v2"
  user         = authentik_user.admin.id
  intent       = "api"
  expiring     = false
  retrieve_key = true
}
