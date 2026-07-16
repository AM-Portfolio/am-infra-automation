/**
 * 🌌 AM-Infra Universal Factory Reset 2.0 (Ultimate Cleanup)
 * Deep Discovery, Tiered Safety Gates, and Post-Cleanup Verification.
 */

const { execSync } = require('child_process');
const readline = require('readline');
const fs = require('fs');
const path = require('path');

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

/**
 * Promisified Readline Question
 */
function ask(question) {
  return new Promise(resolve => rl.question(question, resolve));
}

/**
 * Discovery Engine: Scans Containers, Networks, and Volumes for Kind labels
 */
function discoverClusters() {
  const clusterSet = new Set();
  
  // Try Kind CLI
  try {
    const list = execSync('kind get clusters', { stdio: 'pipe' }).toString().trim();
    if (list && !list.includes('No kind clusters found')) {
      list.split('\n').filter(c => c).forEach(c => clusterSet.add(c.trim()));
    }
  } catch (e) {}

  // Try Docker Labels (Go-template style for keys with dots)
  const filters = [
    'docker ps -a --format "{{.Label \\"io.x-k8s.kind.cluster\\"}}"',
    'docker network ls --format "{{.Label \\"io.x-k8s.kind.cluster\\"}}"',
    'docker volume ls --format "{{.Label \\"io.x-k8s.kind.cluster\\"}}"'
  ];

  filters.forEach(cmd => {
    try {
      const output = execSync(cmd, { stdio: 'pipe' }).toString().trim();
      output.split('\n').filter(c => c && c.trim()).forEach(c => clusterSet.add(c.trim()));
    } catch (e) {}
  });

  return Array.from(clusterSet);
}

/**
 * Finds all volumes associated with specific clusters
 */
function findVolumes(clusters) {
  const volumes = [];
  clusters.forEach(cluster => {
    try {
      const output = execSync(`docker volume ls -q --filter "label=io.x-k8s.kind.cluster=${cluster}"`, { stdio: 'pipe' }).toString().trim();
      if (output) volumes.push(...output.split('\n').filter(v => v));
    } catch (e) {}
  });
  return volumes;
}

/**
 * Purges Infrastructure (Containers & Networks)
 */
function purgeInfrastructure(cluster) {
  console.log(`🗑️  Purging Infra for Cluster: "${cluster}"`);
  
  // Attempt CLI
  try {
    execSync(`kind delete cluster --name ${cluster}`, { stdio: 'ignore' });
    console.log(`  [OK] Removed via Kind CLI.`);
    return;
  } catch (e) {}

  // Fallback: Custom Docker Wipe
  try {
    const containerIds = execSync(`docker ps -a -q --filter "label=io.x-k8s.kind.cluster=${cluster}"`).toString().trim().split('\n');
    if (containerIds.length > 0 && containerIds[0] !== '') {
      execSync('docker rm -f ' + containerIds.join(' '), { stdio: 'ignore' });
      console.log(`  [OK] ${containerIds.length} container(s) purged.`);
    }
  } catch (e) {
    console.log(`  [FAIL] Container purge failed.`);
  }

  // Cleanup Docker Network
  try {
    // Kind creates a network named 'kind' by default
    execSync('docker network rm kind -f', { stdio: 'ignore' });
    console.log(`  [OK] Default "kind" network purged.`);
  } catch (e) {}
}

/**
 * Purges a specific Volume
 */
function purgeVolume(vol) {
  try {
    execSync(`docker volume rm ${vol} -f`, { stdio: 'ignore' });
    console.log(`  [OK] Volume "${vol}" destroyed.`);
  } catch (e) {
    console.log(`  [FAIL] Could not remove volume "${vol}".`);
  }
}

/**
 * Purges local TF state files across ALL layers (Vault-First pipeline).
 * Covers: foundation, vault, gateway, identity, data-stores, monitoring, platform, exposer
 */
function purgeState(env = 'local') {
  const TF_DIR = path.join(__dirname, '../../terraform');

  const LAYERS = [
    'foundation', 'vault', 'gateway', 'identity',
    'data-stores', 'monitoring', 'platform', 'exposer',
  ];

  let cleared = 0;
  LAYERS.forEach(layer => {
    const layerDir = path.join(TF_DIR, layer, env);
    if (!fs.existsSync(layerDir)) return;
    try {
      fs.readdirSync(layerDir)
        .filter(f => f.startsWith('terraform.tfstate') || f === '.terraform.lock.hcl')
        .forEach(f => {
          fs.unlinkSync(path.join(layerDir, f));
          console.log(`  [OK] Erased: ${layer}/${env}/${f}`);
          cleared++;
        });
    } catch (e) {
      console.log(`  [WARN] Could not clean ${layer}: ${e.message}`);
    }
  });

  if (cleared === 0) {
    console.log('  [INFO] No state files found to clear.');
  } else {
    console.log(`  [OK] ${cleared} state file(s) erased across ${LAYERS.length} layers.`);
  }

  // Also wipe the Vault unseal key K8s secret if the cluster is still running
  try {
    execSync('kubectl delete secret vault-unseal-keys -n vault --ignore-not-found', { stdio: 'ignore' });
    console.log('  [OK] Vault unseal key secret cleared from Kubernetes.');
  } catch (e) {}
}

/**
 * Final Cleanliness Verification
 */
function verifyCleanliness(clusters) {
  clusters.forEach(cluster => {
    console.log(`🔎 Audit: ${cluster}`);
    
    const containers = execSync(`docker ps -a -q --filter "label=io.x-k8s.kind.cluster=${cluster}"`).toString().trim();
    console.log(`  - Containers: ${containers ? '❌ STILL EXISTS' : '✅ CLEAN'}`);

    const volumes = execSync(`docker volume ls -q --filter "label=io.x-k8s.kind.cluster=${cluster}"`).toString().trim();
    console.log(`  - Volumes:    ${volumes ? '❌ STILL EXISTS' : '✅ CLEAN'}`);
    
    // Check if any network remains with this label
    try {
      const nets = execSync(`docker network ls -q --filter "label=io.x-k8s.kind.cluster=${cluster}"`).toString().trim();
      console.log(`  - Custom Nets: ${nets ? '❌ STILL EXISTS' : '✅ CLEAN'}`);
    } catch (e) {}
  });

  // Final Generic Check
  const kindNet = execSync('docker network ls --filter "name=kind" -q').toString().trim();
  console.log(`  - Global Kind Network: ${kindNet ? '⚠️ STILL PERSISTS' : '✅ CLEAN'}`);
}

/**
 * Main Controller
 */
async function main() {
  console.log('\n======================================================');
  console.log(' 🔥  FACTORY RESET 2.0 (ULTIMATE CLEANUP) 🔥  ');
  console.log('======================================================');

  const clusters = discoverClusters();
  if (clusters.length === 0) {
    console.log('✅ Result: No legacy Kubernetes (Kind) resources found on this machine.');
    process.exit(0);
  }

  console.log(`\n🔍 Found the following Cluster Identities:`);
  clusters.forEach((c, i) => console.log(`  [${i + 1}] ${c}`));
  console.log(`  [A] ALL clusters`);

  const selection = await ask('\n[1/5] Which cluster do you want to destroy? (Number, Name, or "A"): ');
  let targetClusters = [];
  if (selection.toUpperCase() === 'A' || selection.toUpperCase() === 'ALL') {
    targetClusters = clusters;
  } else {
    const idx = parseInt(selection) - 1;
    if (!isNaN(idx) && clusters[idx]) {
      targetClusters = [clusters[idx]];
    } else if (clusters.includes(selection)) {
      targetClusters = [selection];
    } else {
      console.log('❌ Invalid selection. Aborting.');
      process.exit(1);
    }
  }

  console.log(`\n⚠️  TARGETING INFRASTRUCTURE: [${targetClusters.join(', ')}]`);
  const ansYes = await ask('[2/5] Type "YES" to proceed with Infrastructure Wipe: ');
  if (ansYes !== 'YES') { console.log('✅ Aborted.'); process.exit(0); }

  const ansConfirm = await ask('[3/5] Are you absolutely sure? This cannot be undone. Type "CONFIRM": ');
  if (ansConfirm !== 'CONFIRM') { console.log('✅ Aborted.'); process.exit(0); }

  console.log('\n🔓 Security locks deactivated. DESTROYING INFRASTRUCTURE...');
  targetClusters.forEach(c => purgeInfrastructure(c));

  // TIER 2 SAFETY: DATA VOLUME PURGE
  const volumes = findVolumes(targetClusters);
  if (volumes.length > 0) {
    console.log('\n🛑 SENSITIVE DATA DETECTED (VOLUMES)');
    console.log('The following volumes contain the physical database files:');
    volumes.forEach(v => console.log(`  - ${v}`));
    
    const ansData = await ask('\n[4/5] [SENSITIVE] Type "PURGE DATA" to destroy these volumes forever. \n      Type anything else to SKIP and keep your data safe: ');
    
    if (ansData === 'PURGE DATA') {
      console.log('🔥 OBLITERATING PERSISTENT DATA...');
      volumes.forEach(v => purgeVolume(v));
    } else {
      console.log('✅ DATA PRESERVED. Volume deletion skipped.');
    }
  }

  // TIER 3: STATE MEMORY
  const ansState = await ask('\n[5/5] Do you want to delete the local Terraform state memory? (y/n): ');
  if (ansState.toLowerCase() === 'y') {
    purgeState();
  }

  // FINAL REPORT
  console.log('\n======================================================');
  console.log(' ✅ CLEANLINESS VERIFICATION REPORT');
  console.log('======================================================');
  verifyCleanliness(targetClusters);

  console.log('\n🚀 FACTORY RESET COMPLETE. Run "npm run apply" for a pristine 10/10 build.');
  rl.close();
}

main();
