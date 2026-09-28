#!/usr/bin/env bash
# Check + enable Keycloak OIDC for Vault UI, MinIO, Lago (prod Contabo).
set -euo pipefail
ENV=prod
KCFG=/data/am-state/kubeconfig.am-prod-infra.yaml
CREDS=/data/am-state/credentials/prod
OIDC=$CREDS/oidc.env
VR=$CREDS/vault-root.env
export KUBECONFIG=$KCFG

IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' am-prod-infra-control-plane | awk '{print $1}')
ISSUER=https://auth.asrax.in/realms/am-realm
DISC=$ISSUER/.well-known/openid-configuration

eval "$(grep -E '^(VAULT_ADDR|VAULT_TOKEN)=' $VR | sed 's/\r$//;s/^/export /')"
eval "$(grep -E '^(OIDC_VAULT_UI_|OIDC_MINIO_|OIDC_LAGO_)' $OIDC | sed 's/\r$//;s/^/export /')"

VNP=$(kubectl -n vault get svc vault -o jsonpath='{.spec.ports[?(@.port==8200)].nodePort}')
VADDR=http://${IP}:${VNP}
echo "=== VAULT OIDC ==="
echo "addr=$VADDR"
curl -sf -H "X-Vault-Token: $VAULT_TOKEN" "$VADDR/v1/sys/auth" | python3 -c 'import json,sys; print("auth", sorted(k for k in json.load(sys.stdin) if k.endswith("/")))'
curl -sf -H "X-Vault-Token: $VAULT_TOKEN" "$VADDR/v1/auth/oidc/config" | python3 -c 'import json,sys; d=json.load(sys.stdin).get("data",{}); print("client",d.get("oidc_client_id")); print("discovery",d.get("oidc_discovery_url")); print("default_role",d.get("default_role"))'
# tune already set; print login hint
echo "UI https://vault.asrax.in/ui/vault/auth?with=oidc"

echo "=== MINIO OIDC ==="
# Find minio workload
MINIO_NS=infra
if kubectl -n $MINIO_NS get sts minio >/dev/null 2>&1; then
  KIND=sts; NAME=minio
elif kubectl -n $MINIO_NS get deploy minio >/dev/null 2>&1; then
  KIND=deploy; NAME=minio
else
  kubectl get sts,deploy -A 2>/dev/null | grep -i minio | head -10 || true
  KIND=; NAME=
fi
if [[ -n "${NAME:-}" ]]; then
  echo "workload $KIND/$NAME ns=$MINIO_NS"
  kubectl -n $MINIO_NS get $KIND $NAME -o yaml | grep -E 'MINIO_IDENTITY_OPENID' | sed 's/^\s*//' || echo "NO_OPENID_ENV"
fi

MINIO_SECRET="${OIDC_MINIO_CLIENT_SECRET:-}"
MINIO_ID="${OIDC_MINIO_CLIENT_ID:-minio}"
if [[ -z "$MINIO_SECRET" ]]; then
  echo "WARN no OIDC_MINIO_CLIENT_SECRET in oidc.env"
else
  # Patch / ensure env on StatefulSet or Deployment
  if [[ -n "${NAME:-}" ]]; then
    # Use kubectl set env
    kubectl -n $MINIO_NS set env $KIND/$NAME \
      MINIO_IDENTITY_OPENID_CONFIG_URL="$DISC" \
      MINIO_IDENTITY_OPENID_CLIENT_ID="$MINIO_ID" \
      MINIO_IDENTITY_OPENID_CLIENT_SECRET="$MINIO_SECRET" \
      MINIO_IDENTITY_OPENID_DISPLAY_NAME="Keycloak" \
      MINIO_IDENTITY_OPENID_SCOPES="openid,profile,email,roles,groups" \
      MINIO_IDENTITY_OPENID_REDIRECT_URI="https://minio.asrax.in/oauth_callback" \
      MINIO_IDENTITY_OPENID_CLAIM_NAME="groups" \
      MINIO_BROWSER_REDIRECT_URL="https://minio.asrax.in" \
      || true
    # Also try console host minio.asrax.in variants used in fleet
    kubectl -n $MINIO_NS rollout status $KIND/$NAME --timeout=120s || true
    echo "minio openid env set; verify:"
    kubectl -n $MINIO_NS get $KIND $NAME -o yaml | grep -E 'MINIO_IDENTITY_OPENID' | sed 's/^\s*//' | sed 's/CLIENT_SECRET=.*/CLIENT_SECRET=***/'
  fi
fi

echo "=== LAGO oauth2-proxy ==="
# Ensure oauth2-proxy for lago exists; if not, deploy lightweight one
if kubectl -n billing get deploy oauth2-proxy-lago >/dev/null 2>&1 || kubectl -n billing get deploy lago-oauth2-proxy >/dev/null 2>&1; then
  kubectl -n billing get deploy | grep -i oauth || true
else
  LAGOSECRET="${OIDC_LAGO_CLIENT_SECRET:-}"
  if [[ -z "$LAGOSECRET" ]]; then
    echo "WARN no OIDC_LAGO_CLIENT_SECRET — cannot deploy lago oauth2-proxy"
  else
    COOKIE=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)
    # upstream service name
    UP=http://lago-front-svc.billing.svc:80
    kubectl -n billing get svc 2>/dev/null | head -20
    if kubectl -n billing get svc lago-front-svc >/dev/null 2>&1; then
      UP=http://lago-front-svc.billing.svc:80
    elif kubectl -n billing get svc lago-front >/dev/null 2>&1; then
      UP=http://lago-front.billing.svc:80
    fi
    cat >/tmp/oauth2-lago.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: oauth2-proxy-lago
  namespace: billing
type: Opaque
stringData:
  client-secret: "$LAGOSECRET"
  cookie-secret: "$COOKIE"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: oauth2-proxy-lago
  namespace: billing
spec:
  replicas: 1
  selector:
    matchLabels: { app: oauth2-proxy-lago }
  template:
    metadata:
      labels: { app: oauth2-proxy-lago }
    spec:
      containers:
        - name: oauth2-proxy
          image: quay.io/oauth2-proxy/oauth2-proxy:v7.6.0
          args:
            - --provider=oidc
            - --oidc-issuer-url=$ISSUER
            - --client-id=lago
            - --client-secret=\$(CLIENT_SECRET)
            - --cookie-secret=\$(COOKIE_SECRET)
            - --cookie-secure=true
            - --email-domain=*
            - --upstream=$UP
            - --http-address=0.0.0.0:4180
            - --redirect-url=https://lago.asrax.in/oauth2/callback
            - --oidc-groups-claim=groups
            - --allowed-group=am-admin
            - --allowed-group=am-ops
            - --allowed-group=am-viewer
            - --scope=openid email profile roles groups
            - --skip-provider-button=true
          env:
            - name: CLIENT_SECRET
              valueFrom: { secretKeyRef: { name: oauth2-proxy-lago, key: client-secret } }
            - name: COOKIE_SECRET
              valueFrom: { secretKeyRef: { name: oauth2-proxy-lago, key: cookie-secret } }
          ports:
            - containerPort: 4180
---
apiVersion: v1
kind: Service
metadata:
  name: oauth2-proxy-lago
  namespace: billing
spec:
  selector: { app: oauth2-proxy-lago }
  ports:
    - port: 4180
      targetPort: 4180
      name: http
EOF
    # Fix args - oauth2-proxy doesn't expand $(CLIENT_SECRET) in args that way; use env vars
    cat >/tmp/oauth2-lago.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: oauth2-proxy-lago
  namespace: billing
type: Opaque
stringData:
  client-secret: "$LAGOSECRET"
  cookie-secret: "$COOKIE"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: oauth2-proxy-lago
  namespace: billing
spec:
  replicas: 1
  selector:
    matchLabels: { app: oauth2-proxy-lago }
  template:
    metadata:
      labels: { app: oauth2-proxy-lago }
    spec:
      containers:
        - name: oauth2-proxy
          image: quay.io/oauth2-proxy/oauth2-proxy:v7.6.0
          args:
            - --provider=oidc
            - --oidc-issuer-url=$ISSUER
            - --client-id=lago
            - --cookie-secure=true
            - --email-domain=*
            - --upstream=$UP
            - --http-address=0.0.0.0:4180
            - --redirect-url=https://lago.asrax.in/oauth2/callback
            - --oidc-groups-claim=groups
            - --allowed-group=am-admin
            - --allowed-group=am-ops
            - --allowed-group=am-viewer
            - --scope=openid email profile roles groups
            - --skip-provider-button=true
          env:
            - name: OAUTH2_PROXY_CLIENT_SECRET
              valueFrom: { secretKeyRef: { name: oauth2-proxy-lago, key: client-secret } }
            - name: OAUTH2_PROXY_COOKIE_SECRET
              valueFrom: { secretKeyRef: { name: oauth2-proxy-lago, key: cookie-secret } }
          ports:
            - containerPort: 4180
---
apiVersion: v1
kind: Service
metadata:
  name: oauth2-proxy-lago
  namespace: billing
spec:
  selector: { app: oauth2-proxy-lago }
  ports:
    - port: 4180
      targetPort: 4180
      name: http
EOF
    kubectl apply -f /tmp/oauth2-lago.yaml
    echo "deployed oauth2-proxy-lago upstream=$UP"
  fi
fi

# Point Traefik + NodePort for lago → oauth2-proxy (CF tunnel hits Traefik; NodePort 30830 is fallback)
echo "=== Traefik/NodePort lago → oauth2-proxy ==="
if kubectl -n billing get svc oauth2-proxy-lago >/dev/null 2>&1; then
  if kubectl -n billing get ingressroute.traefik.io lago >/dev/null 2>&1; then
    kubectl -n billing patch ingressroute.traefik.io lago --type=json -p='[
      {"op":"replace","path":"/spec/routes/0/services","value":[{"name":"oauth2-proxy-lago","port":4180}]}
    ]' || true
  fi
  cat >/tmp/lago-ir.yaml <<'EOF'
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: lago-oidc
  namespace: billing
spec:
  entryPoints: [websecure]
  routes:
    - match: Host(`lago.asrax.in`)
      kind: Rule
      priority: 100
      services:
        - name: oauth2-proxy-lago
          port: 4180
EOF
  kubectl apply -f /tmp/lago-ir.yaml || \
  kubectl apply --validate=false -f /tmp/lago-ir.yaml || \
  echo "WARN could not apply IngressRoute"
  if kubectl -n billing get svc lago-front-nodeport >/dev/null 2>&1; then
    kubectl -n billing patch svc lago-front-nodeport --type=json -p='[
      {"op":"replace","path":"/spec/selector","value":{"app":"oauth2-proxy-lago"}},
      {"op":"replace","path":"/spec/ports","value":[{"name":"http","port":80,"targetPort":4180,"nodePort":30830,"protocol":"TCP"}]}
    ]' || true
  fi
fi

echo "=== HTTP probes (expect 302 to Keycloak or login) ==="
for u in \
  "https://vault.asrax.in/ui/vault/auth?with=oidc" \
  "https://minio.asrax.in" \
  "https://lago.asrax.in"
 do
  code=$(curl -sI -o /tmp/h.txt -w "%{http_code}" --max-time 15 "$u" || echo err)
  loc=$(grep -i '^location:' /tmp/h.txt | head -1 | tr -d '\r')
  echo "$code $u"
  echo "  $loc"
done

echo "DONE"
echo "Vault: https://vault.asrax.in/ui/vault/auth?with=oidc  (am-admin-test)"
echo "MinIO: https://minio.asrax.in → Login with OpenID / Keycloak"
echo "Lago: https://lago.asrax.in → 302 via oauth2-proxy to Keycloak"
