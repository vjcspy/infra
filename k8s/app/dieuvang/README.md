# dieuvang

Magento 2.4.9 (MariaDB 11.8, OpenSearch 3, Valkey) + Next.js storefront on `https://dieuvang.bluestone.systems`,
one release `dieuvang` in namespace `dieuvang`. Manually operated: **use `scripts/deploy.sh` on the server, never
`helm upgrade` / `kubectl scale` directly** (replica counts are state-driven; the chart has no replica defaults).

This repository is public: no secret is in the chart. Passwords, the admin frontName and the Marketplace keys live in
k8s Secrets created by `deploy.sh bootstrap` (and one created by hand before it, see the runbook).

```bash
ssh k8s.aws
cd /home/ec2-user/infra && git pull --ff-only
cd k8s/app/dieuvang/scripts
./deploy.sh status
setsid -f ./deploy.sh storefront > /tmp/dv-storefront.log 2>&1   # long runs: detach and tail the log
./deploy.sh magento | storefront | seed | rollback-storefront | reap | bootstrap
```

Full procedure, state files, recovery, capacity numbers and credentials:
`resources/workspaces/k/dv/_guides/__runbooks/261003-dieuvang-k3s-deploy.md` (aweave repo).
