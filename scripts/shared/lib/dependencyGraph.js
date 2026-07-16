const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// ============================================================================
// ENTERPRISE DEPENDENCY GRAPH — Vault-First Pipeline
// Execution order:
//   foundation → vault → gateway → identity → access → data-stores → monitoring → platform
//
// Every layer reads its secrets from Vault. No layer should accept raw tokens
// directly as Terraform variables from manage.js (except 'vault' itself on
// first boot, when it seeds the secrets).
// ============================================================================

const DEPENDENCY_GRAPH = {
    'foundation':   [],
    'vault':        ['foundation'],
    'gateway':      ['foundation', 'vault'],
    'identity':     ['foundation', 'vault', 'gateway'],
    'access':       ['foundation', 'vault', 'gateway', 'identity'],
    'data-stores':  ['foundation', 'vault', 'gateway', 'identity', 'access'],
    'monitoring':   ['foundation', 'vault', 'gateway', 'identity', 'access', 'data-stores'],
    'platform':     ['foundation', 'vault', 'gateway', 'identity', 'access', 'data-stores'],
    'exposer':      ['foundation'],
};

function getDependencies(pkg) {
    return DEPENDENCY_GRAPH[pkg] || [];
}

/**
 * Verifies if a dependency has been built by evaluating its tfstate file.
 */
function checkDependencyState(baseDir, pkg, envName) {
    const statePath = path.join(baseDir, pkg, envName, 'terraform.tfstate');
    if (fs.existsSync(statePath)) {
        try {
            const state = JSON.parse(fs.readFileSync(statePath, 'utf8'));
            if (state.resources && state.resources.length > 0) {
                return true;
            }
        } catch(e) {
            return false;
        }
    }
    return false;
}

/**
 * Synchronously fulfills missing dependencies
 */
function fulfillDependencies(baseDir, targetPkg, config) {
    if (config.isRemote) return; // For now, auto-fulfill only runs locally to avoid remote complexities

    const deps = getDependencies(targetPkg);
    for (const dep of deps) {
        if (!checkDependencyState(baseDir, dep, config.envName)) {
            console.log(`\n⚠️  DEPENDENCY MISSING: Package '${targetPkg}' requires '${dep}'.`);
            console.log(`🚀 Auto-Fulfilling Dependency: Deploying '${dep}' first...\n`);
            
            const depWorkDir = path.join(baseDir, dep, config.envName);
            
            try {
                 execSync(`terraform init`, { cwd: depWorkDir, stdio: 'inherit', shell: true });
                 execSync(`terraform apply -auto-approve`, { cwd: depWorkDir, stdio: 'inherit', shell: true });
                 console.log(`✅ Dependency '${dep}' resolved successfully.\n`);
            } catch (e) {
                 console.error(`❌ Failed to fulfill dependency '${dep}'. Halting orchestration.`);
                 process.exit(1);
            }
        }
    }
}

module.exports = { getDependencies, checkDependencyState, fulfillDependencies, DEPENDENCY_GRAPH };
