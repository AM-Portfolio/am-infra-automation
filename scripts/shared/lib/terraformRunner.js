const { spawn, execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

let hasSyncedThisProcess = false;

function syncToRemote(config, sourceDir) {
    if (!config.isRemote || hasSyncedThisProcess) return;

    console.log(`\n🔄 Syncing local code to VPS [${config.sshHost}]...`);
    const remoteDest = `${config.sshHost}:${config.remoteBase}/`;

    const sshPortOpt = config.sshPort ? `-p ${config.sshPort}` : '';
    const scpPortOpt = config.sshPort ? `-P ${config.sshPort}` : '';

    try {
        // Ensure remote base exists
        execSync(`ssh -o StrictHostKeyChecking=no ${sshPortOpt} ${config.sshHost} "mkdir -p ${config.remoteBase}"`, { stdio: 'ignore' });

        // Use rsync for lightning-fast differential sync (excludes node_modules, .git, and .terraform)
        const sshCmd = config.sshPort ? `ssh -o StrictHostKeyChecking=no -p ${config.sshPort}` : 'ssh -o StrictHostKeyChecking=no';
        const cmd = `rsync -avz --delete -e "${sshCmd}" --exclude='.terraform/' --exclude='.terraform.lock.hcl' --exclude='.git/' --exclude='node_modules/' "${sourceDir}" "${config.sshHost}:${config.remoteBase}"`;
        execSync(cmd, { stdio: 'ignore' });

        hasSyncedThisProcess = true;
        console.log(`✅ Sync successful.\n`);
    } catch (e) {
        console.error(`❌ Sync failed. Remote execution might use stale files: ${e.message}`);
        process.exit(1);
    }
}

/**
 * Executes a terraform command and returns a promise that resolves with the exit code.
 */
function runTerraform(config, command, tfArgs) {
    return new Promise((resolve) => {
        let terraformBin = config.bin;
        if (config.envName === 'local' && !fs.existsSync(terraformBin)) {
            terraformBin = 'terraform'; // Fallback to global if local binary missing
        }

        // If command is not already in tfArgs, prepend it (safeguard)
        const finalArgs = [...tfArgs];
        if (finalArgs[0] !== command) {
            finalArgs.unshift(command);
        }

        // ── PERSISTENCE & MIGRATION LOGIC ───────────────────────────────────────
        let stateFile = null;
        const stateArg = finalArgs.find(a => a.startsWith('-state='));
        const backendArg = finalArgs.find(a => a.startsWith('-backend-config=path='));

        if (stateArg) stateFile = stateArg.split('=')[1];
        else if (backendArg) stateFile = backendArg.split('=')[2];

        if (config.isRemote) {
            syncToRemote(config, config.localBase || config.baseDir);

            // On VPS: Ensure dir exists and migrate legacy state if it exists
            let remoteSetup = '';
            if (stateFile) {
                let stateDir = path.dirname(stateFile);
                if (config.isRemote) stateDir = stateDir.replace(/\\/g, '/');
                remoteSetup = `mkdir -p ${stateDir} && ([ -f terraform.tfstate ] && [ ! -f ${stateFile} ] && mv terraform.tfstate ${stateFile} || true) && `;
            }

            // Securely forward all TF_VAR_ environment variables across the SSH boundary
            let envVars = '';
            for (const key of Object.keys(process.env)) {
                if (key.startsWith('TF_VAR_')) {
                    // Export variables directly into the remote shell command
                    envVars += `export ${key}='${process.env[key].replace(/'/g, "'\\''")}' && `;
                }
            }

            let extraForwards = '';
            let extraPids = '';
            if (config.workDir.includes('identity') || config.workDir.includes('access')) {
                extraForwards = `kubectl --kubeconfig /data/am-state/am-preprod-config port-forward svc/authentik-server 9001:80 -n identity > /dev/null 2>&1 & AUTH_PID=\\$! ; kubectl --kubeconfig /data/am-state/am-preprod-config port-forward svc/authentik-postgres 5432:5432 -n identity > /dev/null 2>&1 & PG_PID=\\$! ; `;
                extraPids = ` ; kill \\$AUTH_PID \\$PG_PID 2>/dev/null || true`;
            }

            const isExposer = config.workDir.includes('exposer');
            const isFoundation = config.workDir.includes('foundation');
            const needsVault = !isExposer && !isFoundation;

            const vaultForward = needsVault ? `kubectl --kubeconfig /data/am-state/am-preprod-config port-forward svc/vault 8200:8200 -n vault > /dev/null 2>&1 & KUBEPID=\\$! ; ` : '';
            
            // Build trap cleanup command using a quote-free shell function to avoid quoting collisions
            let cleanupPids = [];
            if (needsVault) cleanupPids.push('\\$KUBEPID');
            if (config.workDir.includes('identity') || config.workDir.includes('access')) {
                cleanupPids.push('\\$AUTH_PID', '\\$PG_PID');
            }
            const trapCmd = cleanupPids.length > 0 ? `cleanup() { kill ${cleanupPids.join(' ')} 2>/dev/null || true; }; trap cleanup EXIT && ` : '';

            const sshPortOpt = config.sshPort ? `-p ${config.sshPort}` : '';
            const remoteCmd = `cd ${config.workDir} && ${remoteSetup}${vaultForward}${extraForwards}cd ${config.workDir} && sleep 5 ; ${trapCmd}${envVars}${terraformBin} ${finalArgs.join(' ')}`;
            const encodedCmd = Buffer.from(remoteCmd).toString('base64');
            const sshCmd = `ssh -o StrictHostKeyChecking=no ${sshPortOpt} ${config.sshHost} "echo '${encodedCmd}' | base64 -d | bash -l"`;
            spawn(sshCmd, {
                shell: true,
                stdio: 'inherit'
            }).on('close', (code) => resolve({ code }));
        } else {
            // Local Mac: Ensure dir exists and migrate legacy state
            if (stateFile) {
                const stateDir = path.dirname(stateFile);
                if (!fs.existsSync(stateDir)) fs.mkdirSync(stateDir, { recursive: true });

                const legacyState = path.join(config.workDir, 'terraform.tfstate');
                if (fs.existsSync(legacyState) && !fs.existsSync(stateFile)) {
                    console.log(`📦 [MIGRATION] Moving local state to persistent storage...`);
                    fs.renameSync(legacyState, stateFile);
                }
            }

            spawn(terraformBin, finalArgs, {
                cwd: config.workDir,
                shell: true,
                stdio: 'inherit'
            }).on('close', (code) => resolve({ code }));
        }
    });
}

module.exports = { syncToRemote, runTerraform };
