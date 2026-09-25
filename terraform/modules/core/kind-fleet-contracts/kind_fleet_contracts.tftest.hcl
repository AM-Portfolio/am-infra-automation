# Static contracts for kind-fleet edge/bridge/n8n (no cluster or Cloudflare).
#   terraform -chdir=terraform/modules/core/kind-fleet-contracts init -backend=false
#   terraform -chdir=terraform/modules/core/kind-fleet-contracts test

run "prod_product_hosts_and_apex" {
  command = plan
  variables {
    environment = "prod"
    root_domain = "asrax.in"
    https_names = ["am", "corp", "asrax", "auth", "n8n"]
    extra_fqdns = ["asrax.in"]
  }
  assert {
    condition = (
      output.https_fqdn["am"] == "am.asrax.in" &&
      output.https_fqdn["corp"] == "corp.asrax.in" &&
      output.https_fqdn["asrax"] == "asrax.asrax.in" &&
      output.https_fqdn["asrax.in"] == "asrax.in"
    )
    error_message = "prod product hosts and apex must be bare *.asrax.in / asrax.in"
  }
}

run "dev_env_suffix_and_bare" {
  command = plan
  variables {
    environment      = "dev"
    root_domain      = "asrax.in"
    https_names      = ["auth", "grafana"]
    bare_https_names = ["grafana"]
  }
  assert {
    condition = (
      output.https_fqdn["auth"] == "auth-dev.asrax.in" &&
      output.https_fqdn["grafana"] == "grafana.asrax.in"
    )
    error_message = "dev must suffix auth; bare_https_names stay unsuffixed"
  }
}

run "bridge_host_match" {
  command = plan
  variables {
    host_fqdns = ["am.asrax.in", "asrax.asrax.in", "corp.asrax.in", "asrax.in"]
  }
  assert {
    condition = output.host_match == "Host(`am.asrax.in`) || Host(`asrax.asrax.in`) || Host(`corp.asrax.in`) || Host(`asrax.in`)"
    error_message = "bridge host_match must join Host() with || for product UI FQDNs"
  }
}

run "n8n_nodeport_main_only" {
  command = plan
  assert {
    condition = (
      output.n8n_nodeport_selector["app.kubernetes.io/component"] == "main" &&
      output.n8n_nodeport_selector["app.kubernetes.io/name"] == "n8n"
    )
    error_message = "n8n NodePort must select component=main (not workers)"
  }
}
