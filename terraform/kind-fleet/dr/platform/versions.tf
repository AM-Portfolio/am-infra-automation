terraform {
  required_version = ">= 1.5.0"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.2.0"
    }
  }

  # State is on the host, never in git. Default local file is gitignored.
  # Init on the host with: terraform init -backend-config=backend.hcl
  backend "local" {}
}
