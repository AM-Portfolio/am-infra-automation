/**
 * 🔐 AM-Infrastructure — Vault-First Environment Manager
 *
 * This module handles the dual-source credential resolution:
 *   1. Local `.env` (The Baseline/Seed)
 *   2. Vault KV-V2 (The Source of Truth)
 */

'use strict';

const fs = require('fs');
const path = require('path');
const http = require('http');

const VAULT_ADDR = 'http://127.0.0.1:8200';

// ── Vault KV paths that map to .env keys ──────────────────────────────────────
const VAULT_SECRET_MAP = {
  'infra/gateway': {
    cloudflare_token: 'CLOUDFLARE_TOKEN',
    cloudflare_account_id: 'CLOUDFLARE_ACCOUNT_ID',
    cloudflare_zone_id: 'CLOUDFLARE_ZONE_ID',
    cloudflare_tunnel_secret: 'CLOUDFLARE_TUNNEL_SECRET',
  },
  'infra/databases': {
    postgresql_password: 'POSTGRESQL_PASSWORD',
    mongodb_password: 'MONGODB_PASSWORD',
    redis_password: 'REDIS_PASSWORD',
    influxdb_token: 'INFLUXDB_TOKEN',
    grafana_password: 'GRAFANA_PASSWORD',
  },
  'infra/identity': {
    authentik_token: 'AUTHENTIK_TOKEN',
    authentik_secret_key: 'AUTHENTIK_SECRET_KEY',
  },
  'infra/platform': {
    github_pat: 'GITHUB_PAT',
    runner_labels: 'RUNNER_LABELS',
  },
  'infra/admin': {
    headlamp_token: 'HEADLAMP_TOKEN',
  },
  'infra/oidc-data-stores': {
    grafana_client_id: 'GRAFANA_CLIENT_ID',
    grafana_client_secret: 'GRAFANA_CLIENT_SECRET',
    headlamp_client_id: 'HEADLAMP_CLIENT_ID',
    headlamp_client_secret: 'HEADLAMP_CLIENT_SECRET',
    oidc_issuer_url: 'OIDC_ISSUER_URL',
  },
};

// ── Helpers ───────────────────────────────────────────────────────────────────

function injectEnv(kvMap) {
  for (const [key, value] of Object.entries(kvMap)) {
    if (value === undefined || value === null) continue;
    process.env[`TF_VAR_${key.toLowerCase()}`] = value;
    process.env[key] = value;
  }
}

function resolveVaultToken(baseDir) {
  if (process.env.VAULT_TOKEN) return process.env.VAULT_TOKEN;

  const credFile = path.join(baseDir, 'credentials.txt');
  if (fs.existsSync(credFile)) {
    const lines = fs.readFileSync(credFile, 'utf8').split('\n');
    for (const line of lines) {
      const m = line.match(/^(?:vault_root_token|root_token)\s*[=:]\s*(.+)$/i);
      if (m) return m[1].trim();
    }
  }

  // Fallback to .env seeded value if any
  return process.env.VAULT_ROOT_TOKEN || process.env.TF_VAR_vault_root_token || null;
}

function httpGet(url, token) {
  return new Promise((resolve, reject) => {
    const opts = new URL(url);
    const req = http.request({
      hostname: opts.hostname,
      port: opts.port || 8200,
      path: opts.pathname,
      method: 'GET',
      headers: { 'X-Vault-Token': token },
      timeout: 3000,
    }, (res) => {
      let body = '';
      res.on('data', (c) => body += c);
      res.on('end', () => {
        if (res.statusCode === 200) {
          try { resolve(JSON.parse(body)); } catch (_) { reject(new Error('Bad JSON')); }
        } else {
          reject(new Error(`HTTP ${res.statusCode}`));
        }
      });
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
    req.end();
  });
}

// ── Main API ──────────────────────────────────────────────────────────────────

/**
 * PHASE 1: Baseline Load
 * Loads .env file immediately. Does NOT attempt to talk to Vault.
 * Used for bootstrapping and providing initial seed data.
 */
function loadBaseline(baseDir, env = 'preprod') {
  const envPath = path.join(baseDir, '.env');
  const dotEnv = {};
  if (!fs.existsSync(envPath)) {
    console.log(`⚠️  No .env file found at ${envPath}.`);
  } else {
    const lines = fs.readFileSync(envPath, 'utf8').split('\n');
    lines.forEach(line => {
      const trimmed = line.trim();
      if (trimmed && !trimmed.startsWith('#') && trimmed.includes('=')) {
        const [key, ...valueParts] = trimmed.split('=');
        const value = valueParts.join('=').replace(/^["']|["']$/g, '');
        dotEnv[key.trim()] = value;
      }
    });
  }

  // ── Local Credential Cache (Cassay) Check ──
  // Check for credentials.txt in the potential work directories
  const possibleCredPaths = [
    path.join(baseDir, 'credentials.txt'),
    path.join(baseDir, 'terraform/vault/local/credentials.txt')
  ];

  for (const credPath of possibleCredPaths) {
    if (fs.existsSync(credPath)) {
      const credLines = fs.readFileSync(credPath, 'utf8').split('\n');
      credLines.forEach(line => {
        const trimmed = line.trim();
        if (trimmed && trimmed.includes('=')) {
          const [key, value] = trimmed.split('=');
          dotEnv[key.trim().toUpperCase()] = value.trim();
        }
      });
      console.log(`✅ Local credentials cache loaded from ${path.basename(credPath)}`);
    }
  }

  // ── 🛡️ Live Cluster Secret Sync (The 'Ground Truth') ────────────────────────
  // If the pod is running and the secret exists, we refresh our local baseline.
  // This prevents stale .env tokens from causing 403 errors.
  try {
    const { execSync } = require('child_process');
    const os = require('os');
    const kubeconfigPath = path.join(os.homedir(), '.kube', env === 'preprod' ? 'config-am-preprod' : 'am-local-config');
    let kubeconfigOpt = '';
    if (fs.existsSync(kubeconfigPath)) {
      kubeconfigOpt = `--kubeconfig="${kubeconfigPath}"`;
    }
    const secretOutput = execSync(`kubectl ${kubeconfigOpt} get secret vault-unseal-keys -n vault -o json`, { stdio: 'pipe' }).toString();
    const secret = JSON.parse(secretOutput);
    if (secret && secret.data && secret.data['keys.json']) {
      const decoded = Buffer.from(secret.data['keys.json'], 'base64').toString('utf8');
      const keys = JSON.parse(decoded);

      if (keys.root_token) {
        dotEnv['VAULT_ROOT_TOKEN'] = keys.root_token;
        dotEnv['TF_VAR_VAULT_ROOT_TOKEN'] = keys.root_token;
      }
      if (keys.unseal_keys_b64 && keys.unseal_keys_b64[0]) {
        dotEnv['VAULT_UNSEAL_KEY'] = keys.unseal_keys_b64[0];
        dotEnv['TF_VAR_VAULT_UNSEAL_KEY'] = keys.unseal_keys_b64[0];
      }
      console.log(`✅ Live credentials synchronized from cluster secret.`);
    }
  } catch (_) {
    // Cluster or secret not reachable; fallback to .env is already handled.
  }

  injectEnv(dotEnv);
  console.log(`✅ Baseline credentials loaded from .env`);
  return true;
}

/**
 * PHASE 2: Vault Synchronization
 * Attempts to fetch secrets from Vault and OVERRIDE the baseline.
 * Returns true if synchronization succeeded, false otherwise.
 */
async function syncFromVault(baseDir, env = 'preprod') {
  const vaultToken = resolveVaultToken(baseDir);
  if (!vaultToken) {
    console.log(`ℹ️  Vault token not resolved; skipping Vault sync.`);
    return false;
  }

  // Fast health check
  const isHealthy = await new Promise(resolve => {
    const req = http.get(`${VAULT_ADDR}/v1/sys/health`, res => {
      let b = ''; res.on('data', c => b += c);
      res.on('end', () => {
        try { const h = JSON.parse(b); resolve(h.initialized && !h.sealed); } catch (_) { resolve(false); }
      });
    });
    req.on('error', () => resolve(false));
    req.setTimeout(2000, () => { req.destroy(); resolve(false); });
  });

  if (!isHealthy) {
    console.log(`ℹ️  Vault is unreachable or sealed; using .env fallback.`);
    return false;
  }

  let vaultCount = 0;
  const vaultOverrides = {};

  for (const [kvPath, keyMap] of Object.entries(VAULT_SECRET_MAP)) {
    try {
      const resolvedPath = env === 'local' ? kvPath : `${env}/${kvPath}`;
      const url = `${VAULT_ADDR}/v1/secret/data/${resolvedPath}`;
      const res = await httpGet(url, vaultToken);
      const secrets = res.data && res.data.data ? res.data.data : {};

      for (const [vaultKey, envKey] of Object.entries(keyMap)) {
        if (secrets[vaultKey] !== undefined) {
          vaultOverrides[envKey] = secrets[vaultKey];
          vaultCount++;
        }
      }
    } catch (_) { /* Skip missing paths */ }
  }

  if (vaultCount > 0) {
    injectEnv(vaultOverrides);
    console.log(`✅ Credentials synchronized from Vault (${vaultCount} keys overriding .env)`);
    return true;
  }

  console.log(`ℹ️  Vault connected but no overrides found.`);
  return false;
}

module.exports = { loadBaseline, syncFromVault };
