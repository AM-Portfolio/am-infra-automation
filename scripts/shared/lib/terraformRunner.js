const { spawn, execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

let hasSyncedThisProcess = false;

function syncToRemote(config, sourceDir) {
    if (!config.isRemote || hasSyncedThisProcess) return;

    console.log(`\n🔄 Syncing local code to VPS [${config.sshHost}]...`);
    const remoteDest = `${config.sshHost}:${config.remoteBase}/`;

    try {
        // Ensure remote base exists and clean up old terraform folder to prevent scp from nesting it 
        // (i.e. creating terraform/terraform instead of overwriting)
        const remoteTargetDir = `${config.remoteBase}/${path.basename(sourceDir)}`;
        execSync(`ssh -o StrictHostKeyChecking=no ${config.sshHost} "mkdir -p ${config.remoteBase} && rm -rf ${remoteTargetDir}"`, { stdio: 'ignore' });

        // Use SCP for windows-native compatibility
        const cmd = `scp -o BatchMode=yes -o StrictHostKeyChecking=no -r "${sourceDir}" "${remoteDest}"`;
        execSync(cmd, { stdio: 'inherit' });

        // Remove locally-copied MacOS .terraform cache directories on the Linux VPS
        execSync(`ssh -o StrictHostKeyChecking=no ${config.sshHost} "find ${remoteTargetDir} -name '.terraform' -type d -exec rm -rf {} +"`, { stdio: 'ignore' });

        hasSyncedThisProcess = true;
        console.log(`✅ Sync successful.\n`);
    } catch (e) {
        console.error(`❌ Sync failed. Remote execution might use stale files.`);
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

            const remoteCmd = `cd ${config.workDir} && ${remoteSetup}kubectl --kubeconfig /data/am-state/am-preprod-config port-forward svc/vault 8200:8200 -n vault > /dev/null 2>&1 & KUBEPID=$! ; cd ${config.workDir} && sleep 2 ; ${envVars}${terraformBin} ${finalArgs.join(' ')} ; EXITCODE=$? ; kill $KUBEPID 2>/dev/null || true ; exit $EXITCODE`;
            const sshCmd = `ssh -o StrictHostKeyChecking=no ${config.sshHost} "bash -lc '${remoteCmd}'"`;
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
