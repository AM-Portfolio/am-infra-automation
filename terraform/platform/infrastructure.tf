# ── CI/CD RUNNERS ─────────────────────────────────────────────────────────────
# Manages self-hosted GitHub Actions runners within the cluster.
module "github_runner" {
  source          = "../modules/core/github-runner"
  github_pat      = var.github_pat
  github_repo_url = var.github_repo_url
  github_org_name = var.github_org_name
  vps_pass        = var.vps_pass
}

