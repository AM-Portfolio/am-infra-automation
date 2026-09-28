# fleet-gaps — read-only Release Glance gap inventory from Prometheus.
#
# Outputs `gaps` objects:
#   service, env, action (pin|sync|none), mismatch, drift, severity, argo_app, kind, app_ns
#
# Example:
#   module "gaps" {
#     source          = "../../../modules/ops/fleet-gaps"
#     prometheus_url  = "https://prometheus.asrax.in"
#     env_regex       = "prod|dr"
#   }
