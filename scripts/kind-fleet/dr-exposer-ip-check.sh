#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/libexec/am-real:/usr/local/bin:$PATH

EXPOSER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' am-port-exposer)
INFRA_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' am-dr-infra-control-plane)
echo "EXPOSER_IP=$EXPOSER_IP INFRA_IP=$INFRA_IP"

# Host can reach published port?
timeout 3 bash -c '</dev/tcp/127.0.0.1/5432' && echo localhost_pg_ok || echo localhost_pg_fail

# Platform -> exposer:5432 (correct path; public A hairpins)
docker exec am-dr-platform-control-plane bash -c "timeout 3 bash -c '</dev/tcp/${EXPOSER_IP}/5432' && echo exposer_ok || echo exposer_fail"

# Platform -> public A (expected fail)
docker exec am-dr-platform-control-plane bash -c 'timeout 3 bash -c "</dev/tcp/129.121.128.131/5432" && echo public_ok || echo public_fail'
