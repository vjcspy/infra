# Supabase migration plan (Docker Compose ➜ Helm on k3s)

This plan describes how we will migrate the official Supabase Docker Compose stack into a Helm chart under `supabase/` for a single-node k3s cluster, following your requirements.

## Scope and constraints

- Cluster: k3s (single node)
- Ingress controller: nginx
  - Use `spec.ingressClassName: nginx`
  - No TLS section in manifests (nginx fake cert; Cloudflare terminates TLS)
- Storage: hostPath mounted from EBS
  - Root: `/mnt/existing_ebs_volume/supabase/volumes`
  - Every pod using hostPath includes an initContainer that verifies the EBS mount (sentinel file `DONT_DELETE`)
- Configuration: values-only with secrets for sensitive data
  - Secrets for: POSTGRES_PASSWORD, JWT_SECRET, ANON_KEY, SERVICE_ROLE_KEY, DASHBOARD_PASSWORD, SECRET_KEY_BASE, VAULT_ENC_KEY
  - Other env/config are defined in `values.yaml` for simplicity
  - No overrides; keep a clean, readable structure
- Public exposure
  - Kong (API Gateway): `api.bluestone.systems`
  - Studio UI: `studio.bluestone.systems`
  - Do not use subdomain `db`
- Services to deploy immediately
  - Postgres (Deployment)
  - Supavisor (pooler)
  - Auth (GoTrue)
  - PostgREST (REST)
  - Realtime
  - Storage API
  - Imgproxy
  - Postgres Meta
  - Edge Functions
  - Analytics (Logflare)
  - Kong (Gateway)
- Stability: add `wait-for-db` initContainer where it helps startup reliability

## Kubernetes Secret Creation

Before deploying the Helm chart, create a Kubernetes secret containing sensitive values:

```bash
kubectl create secret generic supabase-secrets \
  --from-literal=POSTGRES_PASSWORD="your-super-secret-and-long-postgres-password" \
  --from-literal=JWT_SECRET="your-super-secret-jwt-token-with-at-least-32-characters-long" \
  --from-literal=ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJhbm9uIiwKICAgICJpc3MiOiAic3VwYWJhc2UtZGVtbyIsCiAgICAiaWF0IjogMTY0MTc2OTIwMCwKICAgICJleHAiOiAxNzk5NTM1NjAwCn0.dc_X5iR_VP_qT0zsiyj_I_OZ2T9FtRU2BBNWN8Bu4GE" \
  --from-literal=SERVICE_ROLE_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJzZXJ2aWNlX3JvbGUiLAogICAgImlzcyI6ICJzdXBhYmFzZS1kZW1vIiwKICAgICJpYXQiOiAxNjQxNzY5MjAwLAogICAgImV4cCI6IDE3OTk1MzU2MDAKfQ.DaYlNEoUrrEn2Ig7tqibS-PHK5vgusbcbo7X36XVt4Q" \
  --from-literal=DASHBOARD_PASSWORD="this_password_is_insecure_and_should_be_updated" \
  --from-literal=SECRET_KEY_BASE="UpNVntn3cDxHJpq99YMc1T1AQgQpc8kfYTuRgBiYa15BLrx8etQoXz3gZv1/u2oq" \
  --from-literal=VAULT_ENC_KEY="your-encryption-key-32-chars-min"
```

The Helm templates will reference these secrets using `valueFrom.secretKeyRef` for the corresponding environment variables.

## HostPath layout (under /mnt/existing_ebs_volume/supabase/volumes)

- `db/data/`            → Postgres data directory
- `db/config/`          → Mounted at `/etc/postgresql-custom`
- `db/init/`            → Optional SQL init scripts (if supported by the image)
- `api/kong.yml`        → Kong declarative config file (mounted readOnly via subPath to `/home/kong/temp.yml`)
- `pooler/pooler.exs`   → Supavisor config (mounted readOnly via subPath to `/etc/pooler/pooler.exs`)
- `storage/`            → Storage API data (`/var/lib/storage`)
- `functions/`          → Edge Functions code (`/home/deno/functions`)

We’ll require a sentinel file at `/mnt/existing_ebs_volume/DONT_DELETE` for the EBS mount check.

## InitContainers

- EBS mount check (attached to pods with hostPath):
  - Image: `busybox:1.37.0`
  - Mount: directory `/mnt/existing_ebs_volume` as `/host_ebs_volume`
  - Command: loop-check for `/host_ebs_volume/DONT_DELETE` up to 5 attempts
- wait-for-db (for DB dependents):
  - Image: `busybox:1.37.0`
  - Command: loop until TCP connect to `postgres:5432` (Service DNS) succeeds
  - Enabled by default for: Auth, PostgREST, Realtime, Storage, Meta, Supavisor

## Ingress

- Only for Kong and Studio
- `ingressClassName: nginx`
- No TLS blocks
- Hosts:
  - Kong: `api.bluestone.systems` → Service port 8000 (HTTP)
  - Studio: `studio.bluestone.systems` → Studio Service port (default 3000)

## Kubernetes resources

- One Deployment named `supabase` with multiple containers (Postgres, Supavisor, Auth, PostgREST, Realtime, Storage, Imgproxy, Postgres Meta, Edge Functions, Analytics, Kong, Studio)
- One Service per component (ClusterIP) exposing the corresponding container port(s)
- Two Ingress objects (Kong at `api.bluestone.systems`, Studio at `studio.bluestone.systems`)

Liveness/readiness probes will be added with sensible defaults per component.

## values.yaml structure (single source of truth)

Top-level keys:

- `global.hostPath.root` → `/mnt/existing_ebs_volume/supabase/volumes`
- `global.ingressClassName` → `nginx`
- `ingress`:
  - `kong.host`: `api.bluestone.systems`
  - `studio.host`: `studio.bluestone.systems`
- A section per service with:
  - `enabled`
  - `image: { repository, tag, pullPolicy }`
  - `service: { port }`
  - `env: { ... }` (includes credentials)
  - `resources`, `livenessProbe`, `readinessProbe`
  - `hostPath: { mounts: [...] }` (if applicable)
  - `waitForDb: true|false` (if applicable)

Example skeleton:

```yaml
global:
  hostPath:
    root: /mnt/existing_ebs_volume/supabase/volumes
  ingressClassName: nginx

ingress:
  kong:
    host: api.bluestone.systems
  studio:
    host: studio.bluestone.systems

postgres:
  enabled: true
  image: { repository: supabase/postgres, tag: 15.8.1.060, pullPolicy: IfNotPresent }
  service: { port: 5432 }
  env:
    POSTGRES_DB: app
    POSTGRES_USER: postgres
    POSTGRES_PASSWORD: change-me
    JWT_EXPIRY: "3600"
  hostPath:
    data: "/mnt/existing_ebs_volume/supabase/volumes/db/data"
    config: "/mnt/existing_ebs_volume/supabase/volumes/db/config"
    init: "/mnt/existing_ebs_volume/supabase/volumes/db/init" # optional
  probes: { }

supavisor:
  enabled: true
  image: { repository: supabase/supavisor, tag: 2.5.7, pullPolicy: IfNotPresent }
  service: { port: 6543 }
  env:
    DB_POOL_SIZE: "20"
    DATABASE_URL: postgres://postgres:change-me@postgres:5432/app
  hostPath:
    configFile: "/mnt/existing_ebs_volume/supabase/volumes/pooler/pooler.exs"
  waitForDb: true

auth:
  enabled: true
  image: { repository: supabase/gotrue, tag: v2.177.0, pullPolicy: IfNotPresent }
  service: { port: 9999 }
  env:
    API_EXTERNAL_URL: https://api.bluestone.systems
    GOTRUE_DB_DRIVER: postgres
    GOTRUE_DB_DATABASE_URL: postgres://supabase_auth_admin:change-me@postgres:5432/app
    GOTRUE_JWT_SECRET: change-me
  waitForDb: true

rest:
  enabled: true
  image: { repository: postgrest/postgrest, tag: v12.2.12, pullPolicy: IfNotPresent }
  service: { port: 3000 }
  env:
    PGRST_APP_SETTINGS_JWT_EXP: "3600"
    PGRST_DB_URI: postgres://postgres:change-me@postgres:5432/app
  waitForDb: true

realtime:
  enabled: true
  image: { repository: supabase/realtime, tag: v2.34.47, pullPolicy: IfNotPresent }
  service: { port: 4000 }
  env: { }
  waitForDb: true

storage:
  enabled: true
  image: { repository: supabase/storage-api, tag: v1.25.7, pullPolicy: IfNotPresent }
  service: { port: 5000 }
  env: { }
  hostPath:
    data: "/mnt/existing_ebs_volume/supabase/volumes/storage"
  waitForDb: true

imgproxy:
  enabled: true
  image: { repository: darthsim/imgproxy, tag: v3.8.0, pullPolicy: IfNotPresent }
  service: { port: 8080 }
  env: { }

meta:
  enabled: true
  image: { repository: supabase/postgres-meta, tag: v0.91.0, pullPolicy: IfNotPresent }
  service: { port: 8080 }
  env: { }
  waitForDb: true

functions:
  enabled: true
  image: { repository: supabase/edge-runtime, tag: v1.67.4, pullPolicy: IfNotPresent }
  service: { port: 9000 }
  env:
    VERIFY_JWT: "true"
  hostPath:
    functions: "/mnt/existing_ebs_volume/supabase/volumes/functions"

analytics:
  enabled: true
  image: { repository: supabase/logflare, tag: 1.14.2, pullPolicy: IfNotPresent }
  service: { port: 4000 }
  env:
    LOGFLARE_PUBLIC_ACCESS_TOKEN: xxx
    LOGFLARE_PRIVATE_ACCESS_TOKEN: yyy

kong:
  enabled: true
  image: { repository: kong, tag: 2.8.1, pullPolicy: IfNotPresent }
  service:
    ports:
      http: 8000
      https: 8443
  env:
    KONG_DATABASE: "off"
    KONG_DECLARATIVE_CONFIG: /home/kong/kong.yml
    KONG_PLUGINS: request-transformer,cors,key-auth,acl,basic-auth
    KONG_DNS_ORDER: LAST,A,CNAME
    KONG_NGINX_PROXY_PROXY_BUFFER_SIZE: 160k
    KONG_NGINX_PROXY_PROXY_BUFFERS: "64 160k"
    SUPABASE_ANON_KEY: ...
    SUPABASE_SERVICE_KEY: ...
  hostPath:
    kongConfigFile: "/mnt/existing_ebs_volume/supabase/volumes/api/kong.yml"
```

## Templates (supabase/templates)

- `_helpers.tpl`: extend with hostPath helpers, EBS check partial, wait-for-db partial
- `deployment.yaml`: a single Deployment resource containing all Supabase components as containers (each gated by `.Values.<svc>.enabled`)
- `service.yaml`: a single file emitting all Services (multi-document), one per component
- `ingress.yaml`: a single file emitting both Ingress objects (Kong and Studio), with `ingressClassName: nginx` and no TLS blocks

The Deployment mounts hostPath volumes for the relevant containers and:
- Mounts the appropriate path(s) from `global.hostPath.root`
- Includes the EBS check initContainer
- Note: `wait-for-db` is not used in the current single-Pod model (containers share a network namespace and start together). The helper remains available if you later split services into separate Pods.

## Probes (defaults to be refined during implementation)

- Postgres: TCP readiness on 5432; liveness using `pg_isready`
- Auth: readiness/liveness on `/health`
- PostgREST: readiness on `/` (or `/rpc/health` if defined), liveness TCP 3000
- Realtime: readiness on `/api/health` or TCP 4000
- Storage: readiness on `/health` or TCP 5000
- Meta: TCP 8080
- Functions: TCP 9000
- Analytics: TCP 4000
- Kong: TCP 8000 (and optionally 8443)

## Startup and dependency handling

- DB-first: Postgres must become Ready before dependents start serving.
- Use `wait-for-db` for DB dependents to reduce crashloops.
- Rely on app-level retries otherwise (no `depends_on` in K8s).

## Delivery steps

1) Update `_helpers.tpl` with partials for EBS check and wait-for-db
2) Add values.yaml structure per above (keeping everything in values)
3) Implement a single `deployment.yaml` containing all containers; add hostPath mounts and initContainers where needed
4) Implement a consolidated `service.yaml` containing all Services
5) Implement a consolidated `ingress.yaml` containing Kong and Studio Ingresses (nginx class, no TLS)
7) Add probes and resource defaults; review securityContext/fsGroup for hostPath write access
8) README updates for preparing host directories and sentinel file

## Notes

- We’ll avoid creating Kubernetes Secrets/ConfigMaps per your preference; credentials live in values only.
- No TLS blocks are emitted in Ingress; nginx fake cert + Cloudflare handles TLS.
- Subdomain `db` will not be used for any public endpoint.
