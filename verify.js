const { execSync } = require('child_process');
try {
  execSync('ssh -p 7576 -o StrictHostKeyChecking=no root@103.127.146.57 "ls -la /data/am-repos/am-infra-automation/terraform/foundation/preprod"', { stdio: 'inherit' });
} catch (e) {
  console.error(e.message);
}
