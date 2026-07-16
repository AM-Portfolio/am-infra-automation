/**
 * 🌌 AM-Infrastructure Management Script (v2.0 Modular Orchestrator)
 *
 * Enterprise-grade Terraform wrapper with:
 *  - Vault-First dependency pipeline
 *  - Intelligent Auto-Fulfillment (builds prerequisites automatically)
 *  - Vault-First credential resolution (Vault KV → .env fallback)
 *  - Support for both granular module targets and full package deployment
 *  - Automated Zero-Touch Tunneling for Vault (local dev)
 *  - Two-phase vault:apply (deploy Vault, then seed KV secrets via tunnel)
 *
 * VAULT-FIRST PIPELINE ORDER:
 *   foundation → vault → gateway → identity → access → data-stores → monitoring → platform
 *
 * USAGE:
 *   node manage.js <command> -p <package>          # Deploy a full layer
 *   node manage.js <command> -a <app1,app2>        # Target specific modules inside a layer
 *   node manage.js <command> -p <package> -e preprod
 *
 * COMMANDS: init | plan | apply | destroy | import
 */

const path = require('path');
const { spawn }              = require('child_process');
const { loadBaseline, syncFromVault } = require('../shared/lib/envManager');
const { fulfillDependencies } = require('../shared/lib/dependencyGraph');
const { runTerraform }        = require('../shared/lib/terraformRunner');

const BASE_DIR = path.join(__dirname, '../../');
const TF_DIR   = path.join(__dirname, '../../terraform');

// ── 0. Bootstrap Baseline credentials ───────────────────────────────────────
// We load .env immediately to provide the seed data required for Vault creation.
loadBaseline(BASE_DIR);

(async () => {

// ── 1. APP_MAP — Granular module targeting within a package ─────────────────
const APP_MAP = {
  "cluster":    "module.cluster",
  "bootstrap":  "module.bootstrap",
  "namespaces": "module.namespaces_core",
  "traefik":    "module.traefik_core",
  "cloudflare": "module.cloudflare",
  "authentik":  "module.authentik_core",
  "db-users":   "module.db_users",
  "postgresql": "module.data_stores.module.postgresql",
  "mongodb":    "module.data_stores.module.mongodb",
  "redis":      "module.data_stores.module.redis",
  "influxdb":   "module.data_stores.module.influxdb",
  "kafka":      "module.data_stores.module.kafka",
  "grafana":    "module.monitoring.module.grafana",
  "headlamp":   "module.monitoring.module.headlamp",
  "rover":      "module.monitoring.module.rover",
  "runner":     "module.github_runner",
  "exposer":    "module.port_exposer",
  "access":     "package.access",
  "admin":      "package.admin",
  "dbs":      ["module.data_stores.module.postgresql", "module.data_stores.module.mongodb", "module.data_stores.module.redis", "module.data_stores.module.influxdb"],
  "observe":  ["module.monitoring.module.grafana", "module.monitoring.module.influxdb", "module.monitoring.module.headlamp", "module.monitoring.module.rover"],
};

// ── 2. ARGUMENT PARSING ───────────────────────────────────────────────────────
const args    = process.argv.slice(2);
const command = args[0];
const extraArgs = args.slice(1);

function getArgs(keys) {
  const values = [];
  extraArgs.forEach((arg, index) => {
    const matchedKey = keys.find(key => arg.startsWith(key));
    if (matchedKey) {
      if (arg.includes('=')) {
        values.push(...arg.split('=')[1].split(','));
      } else if (extraArgs[index + 1] && !extraArgs[index + 1].startsWith('-')) {
        values.push(...extraArgs[index + 1].split(','));
      }
    }
  });
  return values;
}

function getArg(keys) {
  const index = extraArgs.findIndex(arg => keys.some(key => arg.startsWith(key)));
  if (index === -1) return null;
  const arg = extraArgs[index];
  return arg.includes('=') ? arg.split('=')[1] : extraArgs[index + 1];
}

const apps   = getArgs(['--apps=', '-apps', '-a']);
const envRaw = getArg(['--env=', '-env', '-e']) || 'preprod';
const env    = envRaw.toLowerCase();
const pkg    = getArg(['--package=', '-package', '-p', '--pkg=']);

// ── 3. MODULE TARGETS ─────────────────────────────────────────────────────────
let targets = [];
apps.forEach(app => {
  const mapped = APP_MAP[app.trim().toLowerCase()];
  if (mapped) {
    if (Array.isArray(mapped)) targets = targets.concat(mapped);
    else targets.push(mapped);
  } else {
    console.warn(`⚠️  Warning: App "${app}" not found in APP_MAP. Using as raw module.`);
    targets.push(`module.${app}`);
  }
});

// ── 4. ENVIRONMENT CONFIG ──────────────────────────────────────────────────────
const STATE_ROOT_REMOTE = "/data/am-state";
const STATE_ROOT_LOCAL  = path.join(BASE_DIR, "terraform", "state");

const ENV_CONFIG = {
  local: {
    baseDir: TF_DIR,
    bin:     path.join(TF_DIR, 'terraform.exe'),
    isRemote: false,
    envName: 'local',
    stateRoot: STATE_ROOT_LOCAL
  },
  preprod: {
    baseDir:    '/data/am-repos/am-infra/terraform',
    bin:        'terraform',
    isRemote:   true,
    envName:    'preprod',
    sshHost:    'root@150.242.202.122',
    localBase:  TF_DIR,
    remoteBase: '/data/am-repos/am-infra',
    stateRoot:  STATE_ROOT_REMOTE
  }
};

const config    = ENV_CONFIG[env] || ENV_CONFIG.local;
config.workDir  = pkg ? path.join(config.baseDir, pkg, config.envName) : config.baseDir;

// ── 4.5 PATH NORMALIZATION FOR REMOTE (FIX SQUASHED PATHS ON WINDOWS) ───────
// If we are on Windows, path.join uses backslashes (\). Linux SSH shells 
// interpret these as escape characters, which squashes paths like "\data\am" 
// into "dataam". We force forward slashes for all remote workDirs.
if (config.isRemote) {
  config.workDir = config.workDir.replace(/\\/g, '/');
}

// Force the system environment to match the CLI environment argument
process.env['TF_VAR_environment'] = config.envName;

// ── 5. TERRAFORM COMMAND ASSEMBLY ─────────────────────────────────────────────
let tfArgs = [];
if (command === 'init') {
  tfArgs.push('init');
} else if (command === 'import') {
  tfArgs.push('import');
  extraArgs.forEach(arg => { if (!arg.startsWith('-')) tfArgs.push(arg); });
} else if (command === 'state') {
  tfArgs.push('state');
  // Pass all following arguments (e.g. rm <address>)
  extraArgs.forEach(arg => { if (!arg.startsWith('-')) tfArgs.push(arg); });
} else {
  tfArgs.push(command);
  if (command === 'apply')   tfArgs.push('-auto-approve');
  if (command === 'destroy') tfArgs.push('-auto-approve');
  targets.forEach(t => tfArgs.push('-target', t));
}

// ── 5.5 PERSISTENT STATE INJECTION ──────────────────────────────────────────
// State is now injected during INIT via backend-config to avoid Terraform CLI parser bugs.
// (Removing the deprecated -state flag here)

// ── 6. VAULT READY HELPER (TUNNEL + WAIT FOR WATCHER) ────────────────────────
//
// NOTE: Unsealing is now the responsibility of the vault-unsealer-watcher
// Kubernetes Deployment (watcher.tf inside modules/apps/vault). That pod runs
// 24/7 inside the cluster and auto-unseals Vault within ~15 seconds of a
// cluster restart — no human or script intervention required.
//
// manage.js only needs to:
//   1. Open a kubectl port-forward to vault:8200 (skips if port already bound)
//   2. Poll /v1/sys/health until Vault is reachable AND unsealed
//   3. If still sealed after 90s, print a helpful hint and exit cleanly
//
// If you see "Vault is sealed — waiting for watcher", just give it ~15-30s.
// ─────────────────────────────────────────────────────────────────────────────

const http = require('http');

/**
 * Poll GET http://127.0.0.1:8200/v1/sys/health until:
 *   - Vault is reachable AND unsealed (sealed === false)  → resolves
 *   - maxWaitMs exceeded                                  → rejects
 *
 * While Vault is sealed the function logs a hint that the watcher is working
 * on it, then retries. This handles the cluster-restart window where Vault
 * comes up sealed for ~5-15s before the watcher unseals it.
 */
function pollVaultHealth(maxWaitMs = 90000, intervalMs = 5000) {
  return new Promise((resolve, reject) => {
    const deadline = Date.now() + maxWaitMs;
    let attempt = 0;

    function check() {
      attempt++;
      const req = http.get('http://127.0.0.1:8200/v1/sys/health', (res) => {
        let body = '';
        res.on('data', (c) => body += c);
        res.on('end', () => {
          let health = {};
          try { health = JSON.parse(body); } catch (_) { /* ignore */ }

          if (health.sealed === false) {
            // Vault is up and unsealed — we're good to go
            resolve(health);
          } else if (health.sealed === true) {
            console.log(`⏳ [VAULT] Vault is sealed — watcher pod is unsealing... (attempt ${attempt})`);
            scheduleRetry();
          } else {
            // Unrecognized body (e.g. Vault not initialized yet)
            console.log(`⏳ [VAULT] Waiting for Vault to initialize... (attempt ${attempt})`);
            scheduleRetry();
          }
        });
      });

      req.setTimeout(3000);
      req.on('error', () => {
        console.log(`⏳ [VAULT] Vault not yet reachable (attempt ${attempt})...`);
        scheduleRetry();
      });
      req.on('timeout', () => { req.destroy(); });
    }

    function scheduleRetry() {
      if (Date.now() >= deadline) {
        return reject(new Error(
          'Vault did not become unsealed within 90 seconds.\n' +
          '  → Check that the Kind cluster is running:   kubectl cluster-info\n' +
          '  → Check the watcher pod logs:                kubectl logs -n vault -l app=vault-unsealer-watcher\n' +
          '  → If watcher is not yet deployed, run first: npm run vault:apply'
        ));
      }
      setTimeout(check, intervalMs);
    }

    check();
  });
}

/**
 * Self-healing tunnel guardian.
 *
 * Problem: `kubectl port-forward` silently exits (EOF) during long-running
 * Terraform plans, severing the Vault provider's HTTP connection mid-operation.
 *
 * Solution: a guardian loop that immediately re-spawns the port-forward
 * whenever it exits, keeping localhost:8200 alive for the entire Terraform run.
 * Returns a { stop } handle so the caller can cleanly tear it down afterward.
 *
 * Pre-flight: if port 8200 is already bound by an external process, we skip
 * spawning kubectl entirely and just monitor for future drops.
 */
function startTunnelGuardian(onReadyOnce) {
  const net = require('net');
  let stopped    = false;
  let current    = null;   // active kubectl child process
  let readyFired = false;

  /** TCP-probe localhost:port → cb(true) if something is listening. */
  function probeTcp(port, cb) {
    const sock = net.connect({ host: '127.0.0.1', port }, () => {
      sock.destroy();
      cb(true);
    });
    sock.setTimeout(1000);
    sock.on('timeout', () => { sock.destroy(); cb(false); });
    sock.on('error',   () => cb(false));
  }

  function monitorExternal() {
    if (stopped) return;
    probeTcp(8200, (still) => {
      if (stopped) return;
      if (!still) {
        console.warn(`⚠️  [TUNNEL] Existing port-forward dropped. Spawning replacement in 2s...`);
        setTimeout(spawnTunnel, 2000);
      } else {
        setTimeout(monitorExternal, 10000);
      }
    });
  }

  function spawnTunnel() {
    if (stopped) return;

    const proc = spawn(
      'kubectl',
      ['port-forward', 'service/vault', '8200:8200', '-n', 'vault'],
      { shell: true, env: process.env }
    );
    current = proc;

    proc.stdout.on('data', (data) => {
      const msg = data.toString();
      if (msg.includes('Forwarding from') && !readyFired) {
        console.log(`✅ [TUNNEL] Vault tunnel established.`);
        readyFired = true;
        onReadyOnce();
      }
    });

    // Suppress noisy stderr; we rely on the exit event + TCP probe instead.
    proc.stderr.on('data', () => {});

    proc.on('exit', (code, signal) => {
      if (stopped) return;
      // Probe: if another process already holds 8200, just monitor passively.
      probeTcp(8200, (reachable) => {
        if (stopped) return;
        if (reachable) {
          console.log(`ℹ️  [TUNNEL] Port 8200 still active via external process. Monitoring...`);
          setTimeout(monitorExternal, 10000);
        } else {
          console.warn(`⚠️  [TUNNEL] Port-forward exited (code=${code}). Restarting in 2s...`);
          setTimeout(spawnTunnel, 2000);
        }
      });
    });
  }

  console.log(`🔌 [TUNNEL] Starting self-healing Vault port-forward (8200:8200)...`);

  // ── Pre-flight: if port 8200 is already bound, skip spawning entirely ────────
  probeTcp(8200, (alreadyUp) => {
    if (stopped) return;
    if (alreadyUp) {
      console.log(`ℹ️  [TUNNEL] Port 8200 already active. Reusing existing tunnel.`);
      readyFired = true;
      onReadyOnce();
      // Monitor for future drops
      setTimeout(monitorExternal, 10000);
    } else {
      spawnTunnel();
      // Safety timeout: if kubectl never prints "Forwarding from" within 15s, proceed anyway
      setTimeout(() => {
        if (!readyFired && !stopped) {
          console.warn(`⚠️  [TUNNEL] No tunnel confirmation after 15s; attempting Vault health check anyway...`);
          readyFired = true;
          onReadyOnce();
        }
      }, 15000);
    }
  });

  return {
    stop() {
      stopped = true;
      if (current && current.kill) {
        current.kill();
        current = null;
      }
    }
  };
}

function ensureVaultReady(callback) {
  const VAULT_SKIP_PKGS = ['foundation'];

  if (env !== 'local' || VAULT_SKIP_PKGS.includes(pkg)) {
    return callback(null);
  }

  const guardian = startTunnelGuardian(() => {
    // Called once when the tunnel is first confirmed ready
    pollVaultHealth()
      .then(() => {
        console.log(`✅ [VAULT] Vault is up and unsealed. Proceeding to Terraform.`);
        callback(guardian);
      })
      .catch((err) => {
        console.error(`\n❌ [VAULT] ${err.message}`);
        guardian.stop();
        process.exit(1);
      });
  });
}

// ── 7. MAIN EXECUTION FLOW ──────────────────────────────────────────────────

async function execute() {
  if (!command) return;

  // ── Step 1: Pre-flight checks & Auto-fulfilment ───────────────────────────
  console.log(`\n======================================================`);
  console.log(` 🚀 AM-ORCHESTRATOR v2.5 — Seed-to-Vault Resolution `);
  console.log(`======================================================`);
  console.log(`🔹  Env:      [${env.toUpperCase()}]`);
  console.log(`🔹  Action:   [${command.toUpperCase()}]`);
  if (pkg)            console.log(`📦  Package:  [${pkg.toUpperCase()}]`);
  if (targets.length) console.log(`🎯  Targets:  ${targets.join(', ')}`);
  console.log(`📂  Dir:      ${config.workDir}`);

  if (command !== 'destroy' && pkg) {
    fulfillDependencies(TF_DIR, pkg, config);
  }

  // ── Step 2: Vault Readiness Window ────────────────────────────────────────
  // For the 'vault' package on apply/plan: two-phase execution.
  //   Phase 1 — deploy only module.vault (Helm/K8s, no Vault provider calls)
  //   Phase 2 — start tunnel, wait for Vault to unseal, apply remaining resources
  //             (vault_mount, vault_kv_secret_v2, etc.)
  // For all other packages that depend on Vault, just ensure the tunnel is up first.
  const isVaultPkg  = pkg === 'vault';
  const isTwoPhase  = isVaultPkg && ['apply', 'plan'].includes(command) && targets.length === 0;
  const isFoundationTwoPhase = pkg === 'foundation' && ['apply', 'plan'].includes(command) && targets.length === 0;
  let activeTunnel  = null;

  // ── Step 3: Run Terraform ─────────────────────────────────────────────────
  console.log(`\n🚀 [TERRAFORM] Executing ${command}...`);

  try {
    // 5. Build Base Arguments
    let stateFile = pkg ? path.join(config.stateRoot, pkg + '.tfstate') : null;
    let kubeconfigPath = pkg ? path.join(config.stateRoot, `am-${config.envName}-config`) : null;

    // Normalize paths for remote (force forward slashes)
    if (config.isRemote) {
        if (stateFile) stateFile = stateFile.replace(/\\/g, '/');
        if (kubeconfigPath) kubeconfigPath = kubeconfigPath.replace(/\\/g, '/');
    }
    
    // 6. Run Terraform Init
    //    We inject the remote state path dynamically during init. 
    //    This natively binds the local backend without triggering the 'apply -state=' CLI parser bug.
    const initArgs = pkg ? (command === 'state' ? [
        `-backend-config=path=${stateFile}`
    ] : [
        `-backend-config=path=${stateFile}`,
        `-var="kubeconfig_path=${kubeconfigPath}"`,
        `-var="kubeconfig_context=kind-am-${config.envName}"`
    ]) : [];
    const initResult = await runTerraform(config, 'init', initArgs);
    if (initResult.code !== 0) {
        console.error(`❌ [INIT] failed (exit ${initResult.code}).`);
        process.exit(initResult.code);
    }

    // 7. Run Requested Command (apply, plan, destroy)
    //    We pass our standard variables. Notice we DO NOT use '-state=' here anymore.
    const opArgs = (pkg && command !== 'state') ? [
        `-var="kubeconfig_path=${kubeconfigPath}"`,
        `-var="kubeconfig_context=kind-am-${config.envName}"`
    ] : [];

    if (isFoundationTwoPhase) {
      console.log(`\n📦 [FOUNDATION] Phase 1 — Provisioning bare cluster to extract Kubeconfig...`);
      // Tell terraform to ONLY evaluate and deploy the cluster module, ignoring the provider blocks that would crash
      const phase1 = await runTerraform(config, command, [...tfArgs, ...opArgs, '-target', 'module.foundation.module.cluster']);
      if (phase1.code !== 0) {
        console.error(`\n❌ [FOUNDATION Phase 1] failed (exit ${phase1.code}).`);
        process.exit(phase1.code);
      }
      console.log(`\n✅ [FOUNDATION Phase 1] Cluster provisioned. Kubeconfig extracted.`);

      console.log(`\n📦 [FOUNDATION] Phase 2 — Deploying Core Namespaces & Drivers...`);
      // Now that the config file is firmly on disk, we can run the whole module naturally
      const phase2 = await runTerraform(config, command, [...tfArgs, ...opArgs]);
      if (phase2.code !== 0) {
        console.error(`\n❌ [FOUNDATION Phase 2] failed (exit ${phase2.code}).`);
        process.exit(phase2.code);
      }
      console.log(`\n✅ [${command.toUpperCase()}] completed successfully.`);
      process.exit(0);

    } else if (isTwoPhase) {
      // ── Phase 1: Deploy Vault infrastructure (no Vault provider needed) ──────
      console.log(`\n📦 [VAULT] Phase 1 — Deploying Vault infrastructure (Helm + K8s)...`);
      const vaultModuleArgs = [...opArgs, '-auto-approve', '-target', 'module.vault', '-var="vault_root_token=bootstrap"'];
      const phase1 = await runTerraform(config, command, vaultModuleArgs);
      if (phase1.code !== 0) {
        console.error(`\n❌ [VAULT Phase 1] failed (exit ${phase1.code}).`);
        process.exit(phase1.code);
      }
      console.log(`\n✅ [VAULT Phase 1] Vault infrastructure deployed.`);

      // ── Phase 2: Wait for Vault to be ready, then seed KV secrets ────────────
      console.log(`\n🔐 [VAULT] Phase 2 — Starting tunnel and waiting for Vault to be unsealed...`);
      activeTunnel = await new Promise((resolve, reject) => {
        ensureVaultReady((tunnel) => {
          if (tunnel instanceof Error) reject(tunnel);
          else resolve(tunnel);
        });
      });

      console.log(`\n📦 [VAULT] Phase 2 — Seeding KV secrets into Vault...`);
      // Apply everything now (module.vault will be a no-op, remainder will seed secrets)
      const phase2 = await runTerraform(config, command, [...opArgs, '-auto-approve']);
      
      if (activeTunnel && activeTunnel.stop) {
        console.log(`🔌 [TUNNEL] Shutting down Vault tunnel guardian...`);
        activeTunnel.stop();
      }

      if (phase2.code !== 0) {
        console.error(`\n❌ [VAULT Phase 2] failed (exit ${phase2.code}).`);
      } else {
        console.log(`\n✅ [${command.toUpperCase()}] completed successfully.`);
      }
      process.exit(phase2.code);

    } else {
      // ── Standard path: ensure Vault tunnel, then run command ─────────────────
      const needsVaultTunnel = env === 'local' && !['foundation'].includes(pkg);
      if (needsVaultTunnel) {
        console.log(`\n🔐 [VAULT] Package '${pkg}' requires Vault. Starting tunnel...`);
        activeTunnel = await new Promise((resolve, reject) => {
          ensureVaultReady((tunnel) => {
            if (tunnel instanceof Error) reject(tunnel);
            else resolve(tunnel);
          });
        });

        // Synchronize Vault secrets to override .env baseline (non-vault packages)
        if (!isVaultPkg) {
          await syncFromVault(BASE_DIR);
        }
      }

      // Execute requested command
      const mainResult = await runTerraform(config, command, [...tfArgs, ...opArgs]);

      if (activeTunnel && activeTunnel.stop) {
        console.log(`🔌 [TUNNEL] Shutting down Vault tunnel guardian...`);
        activeTunnel.stop();
      }

      if (mainResult.code !== 0) {
        console.error(`\n❌ [${command.toUpperCase()}] failed (exit ${mainResult.code}).`);
      } else {
        console.log(`\n✅ [${command.toUpperCase()}] completed successfully.`);
      }
      process.exit(mainResult.code);
    }

  } catch (err) {
    console.error(`\n❌ [TERRAFORM] Fatal error: ${err.message}`);
    if (activeTunnel && activeTunnel.stop) activeTunnel.stop();
    process.exit(1);
  }
}

execute().catch(err => {
  console.error(`\n❌ [ORCHESTRATOR] Unhandled crash: ${err.message}`);
  process.exit(1);
});

})();
