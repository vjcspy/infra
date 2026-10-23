# victoria-logs

VictoriaLogs single-node, the production log store for jmeta and metan (fed by fluent-bit). Data lives on the app EBS
volume at `/mnt/existing_ebs_volume/victoria-logs/`. Canonical usage and ops guide:
`resources/workspaces/k/infrastructure/_guides/victorialogs-production-logs.md` (written in the plan's Step F).

Safety: `replicas: 1` + `strategy: Recreate` (single writer on the hostPath), DONT_DELETE sentinel init container,
root hostPath `type: Directory` with `subPath`. The ingress routes only `/select` behind nginx basic auth.

## Out-of-band Secrets (never in git)

Create once, on the host, with `kubectl` (values come from a local `umask 077` temp dir or stdin; never echo them):

```sh
kubectl create namespace victoria-logs
# htpasswd bcrypt line for user "agent" in key "auth" (used by the ingress)
kubectl -n victoria-logs create secret generic victoria-logs-basic-auth --from-file=auth=<htpasswd-file>
# plaintext copy for recovery (keys: username, password)
kubectl -n victoria-logs create secret generic victoria-logs-agent-credentials \
  --from-literal=username=agent --from-file=password=<password-file>
```

Recover the password on a new machine over SSH (prints a secret, run only into a `chmod 600` file):
`kubectl -n victoria-logs get secret victoria-logs-agent-credentials -o jsonpath='{.data.password}' | base64 -d`.

Password rotation: generate a new password, recreate both Secrets (`kubectl delete secret` then `create`, or
`create --dry-run=client -o yaml | kubectl apply -f -`), update `~/.config/k/victorialogs.env`. nginx reloads the
auth file by itself; no pod restart needed.

## Install / upgrade

```sh
cd /home/ec2-user/infra/k8s/app
KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm upgrade --install victoria-logs victoria-logs -n victoria-logs
```
