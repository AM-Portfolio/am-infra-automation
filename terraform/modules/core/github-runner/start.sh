#!/bin/bash
cd actions-runner

# Load Vault-injected secrets if present
if [ -f /vault/secrets/config ]; then
  tr -d '\r' < /vault/secrets/config > /tmp/runner_env.sh
  source /tmp/runner_env.sh
  rm /tmp/runner_env.sh
fi

# Use native K8s ServiceAccount auth inside the cluster
if [ -d /var/run/secrets/kubernetes.io/serviceaccount ]; then
  rm -rf /home/github/.kube
fi

[ -z "$REPO_URL" ] && echo "ERROR: REPO_URL required" && exit 1
[ -z "$RUNNER_TOKEN" ] && [ -z "$GITHUB_PAT" ] && echo "ERROR: RUNNER_TOKEN or GITHUB_PAT required" && exit 1

export RUNNER_ALLOW_RUNASROOT=1

# Auto-fetch fresh token using PAT
if [ -n "$GITHUB_PAT" ]; then
  ORG_NAME=$(echo "$REPO_URL" | sed -E 's|https://github.com/([^/]+).*|\1|')
  RESPONSE=$(curl -s -L -w "\n%{http_code}" -X POST -H "Accept: application/vnd.github+json" -H "Authorization: Bearer $GITHUB_PAT" -H "X-GitHub-Api-Version: 2022-11-28" "https://api.github.com/orgs/$ORG_NAME/actions/runners/registration-token")
  HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
  BODY=$(echo "$RESPONSE" | head -n -1)
  REG_TOKEN=$(echo "$BODY" | jq -r '.token' 2>/dev/null || echo "")
  [ "$HTTP_CODE" -eq 201 ] && [ -n "$REG_TOKEN" ] && [ "$REG_TOKEN" != "null" ] && RUNNER_TOKEN=$REG_TOKEN
fi

if [ ! -f .runner ]; then
  LABELS="self-hosted,Linux,X64,docker"
  if [ -n "$ADDITIONAL_LABELS" ]; then
    LABELS="$LABELS,$ADDITIONAL_LABELS"
  fi
  ./config.sh --url "$REPO_URL" --token "$RUNNER_TOKEN" --name "docker-runner-$(hostname)" --work "_work" --labels "$LABELS" --unattended --replace
fi

cleanup() {
  if [ -n "$GITHUB_PAT" ]; then
    REMOVE_TOKEN=$(curl -s -X POST -H "Accept: application/vnd.github+json" -H "Authorization: Bearer $GITHUB_PAT" -H "X-GitHub-Api-Version: 2022-11-28" "https://api.github.com/orgs/$ORG_NAME/actions/runners/remove-token" | jq -r '.token' 2>/dev/null)
    [ -n "$REMOVE_TOKEN" ] && [ "$REMOVE_TOKEN" != "null" ] && RUNNER_TOKEN=$REMOVE_TOKEN
  fi
  ./config.sh remove --unattended --token "$RUNNER_TOKEN" || true
}
trap 'cleanup' SIGINT SIGTERM SIGHUP SIGQUIT

echo "🚀 Starting Runner..."
./run.sh &
wait
