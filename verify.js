const { execSync } = require('child_process');
try {
  const out = execSync('ssh -o StrictHostKeyChecking=no root@150.242.202.122 "ls -la /data/am-repos/am-infra/terraform/foundation/preprod"');
  console.log(out.toString());
} catch (e) {
  console.error(e.message);
}
