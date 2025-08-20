# Supabase migration plan (Docker Compose ➜ Helm on k3s)

This plan describes how we will migrate the official Supabase Docker Compose stack into a Helm chart under `supabase/` for a single-node k3s cluster, following your requirements.

## Scope and constraints

- Cluster: k3s (single node)
- Ingress controller: nginx
  - Use `spec.ingressClassName: nginx`
  - No TLS section in manifests (nginx fake cert; Cloudflare terminates TLS)
- Storage: hostPath mounted from EBS
  - Root: `/mnt/ebs_postgres_data/supabase/volumes`
  - Every pod using hostPath includes an initContainer that verifies the EBS mount (sentinel file `DONT_DELETE`)
- Configuration: all env vars and credentials in values.yaml for simplicity
  - No Kubernetes Secrets - all sensitive data is stored in values.yaml
  - Use a custom values file to override sensitive values during deployment
  - Clean, readable structure with all configuration in one place
- Public exposure
  - Kong (API Gateway): `db.bluestone.systems`
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

## Configuration management

All configuration is managed through `values.yaml` for simplicity. Sensitive values are stored in the `secrets` section and can be overridden using custom values files for different environments.

For production deployment, create a custom values file:

```bash
# Create custom values file for production
cat > custom-values.yaml << EOF
secrets:
  postgresPassword: "$(openssl rand -base64 32)"
  jwtSecret: "$(openssl rand -base64 32)"
  anonKey: "your-production-anon-key"
  serviceRoleKey: "your-production-service-key"
  dashboardPassword: "$(openssl rand -base64 16)"
  secretKeyBase: "$(openssl rand -base64 64)"
  vaultEncKey: "$(openssl rand -base64 32)"

# Override other production-specific values
ingress:
  kong:
    host: api.yourdomain.com
  studio:
    host: studio.yourdomain.com
EOF

# Deploy with custom values
kubectl create namespace supabase && helm upgrade --install supabase . -f custom-values.yaml -n supabase
```

This approach eliminates the need for separate Kubernetes secret creation and management.

## HostPath layout (under /mnt/ebs_postgres_data/supabase/volumes)

- `db/data/`            → Postgres data directory
- `db/config/`          → Mounted at `/etc/postgresql-custom`
- `db/init/`            → Optional SQL init scripts (if supported by the image)
- `api/kong.yml`        → Kong declarative config file (mounted readOnly via subPath to `/home/kong/temp.yml`)
- `pooler/pooler.exs`   → Supavisor config (mounted readOnly via subPath to `/etc/pooler/pooler.exs`)
- `storage/`            → Storage API data (`/var/lib/storage`)
- `functions/`          → Edge Functions code (`/home/deno/functions`)

We’ll require a sentinel file at `/mnt/ebs_postgres_data/DONT_DELETE` for the EBS mount check.

InitContainers

- EBS mount check (only once, on Postgres):
  - Image: `busybox:1.37.0`
  - Mount: directory `/mnt/ebs_postgres_data` as `/host_ebs_volume`
  - Command: loop-check for `/host_ebs_volume/DONT_DELETE` up to 5 attempts
  - Note: Other components no longer perform EBS mount checks; Postgres validates the hostPath mount and others rely on the same volume root.
- wait-for-db (for DB dependents):
  - Image: `busybox:1.37.0`
  - Command: loop until TCP connect to `postgres:5432` (Service DNS) succeeds
  - Enabled by default for: Auth, PostgREST, Realtime, Storage, Meta, Supavisor
- depends_on (docker-compose-like) via kubectl rollout:
  - Image: `bitnami/kubectl:latest`
  - Command: `kubectl rollout status deployment/<name> --namespace={{ .Release.Namespace }} --timeout=300s`
  - Used to enforce startup ordering similar to docker-compose:
    - studio → analytics
    - kong → analytics
    - auth → postgres, analytics
    - rest → postgres, analytics
    - realtime → postgres, analytics
    - storage → postgres, rest, imgproxy
    - meta → postgres, analytics
    - functions → analytics
    - supavisor → postgres, analytics

## Ingress

- Only for Kong and Studio
- `ingressClassName: nginx`
- No TLS blocks
- Hosts:
  - Kong: `db.bluestone.systems` → Service port 8000 (HTTP)

## Kubernetes resources

- One Deployment per component (independent Pods), each in its own template file:
  - `deployment-postgres.yaml`
  - `deployment-supavisor.yaml`
  - `deployment-auth.yaml`
  - `deployment-rest.yaml`
  - `deployment-realtime.yaml`
  - `deployment-storage.yaml`
  - `deployment-imgproxy.yaml`
  - `deployment-meta.yaml`
  - `deployment-functions.yaml`
  - `deployment-analytics.yaml`
  - `deployment-kong.yaml`
  - `deployment-studio.yaml`
- One Service per component (ClusterIP), each in its own template file:
  - `service-postgres.yaml`, `service-supavisor.yaml`, `service-auth.yaml`, `service-rest.yaml`, `service-realtime.yaml`, `service-storage.yaml`, `service-imgproxy.yaml`, `service-meta.yaml`, `service-functions.yaml`, `service-analytics.yaml`, `service-kong.yaml`, `service-studio.yaml`
- Optional always-on debug Deployment for troubleshooting: `deployment-debug.yaml` (gated by `.Values.debug.enabled`)
- Two Ingress objects (Kong at `db.bluestone.systems`)
  - Ingress names: `kong` and `studio`

Labeling and selectors:
- All Deployments/Pods and Services include:
  - `app.kubernetes.io/name: supabase`
  - `app.kubernetes.io/instance: {{ .Release.Name }}`
  - `app.kubernetes.io/component: <component>`
- Each Service selector matches the same three labels to route only to its component Pods.

Liveness/readiness probes are configured per component with sensible defaults.

## values.yaml structure (single source of truth)

All configuration is stored in `values.yaml` for simplicity. Sensitive data is in the `secrets` section and can be overridden using custom values files.

Top-level keys:

- `secrets`: All sensitive values (passwords, keys, tokens)
- `global.hostPath.root` → `/mnt/ebs_postgres_data/supabase/volumes`
- `global.ingressClassName` → `nginx`
- `ingress`:
  - `kong.host`: `db.bluestone.systems`
- A section per service with:
  - `enabled`
  - `image: { repository, tag, pullPolicy }`
  - `service: { port }`
  - `env: { ... }` (includes all environment variables, with Helm template expressions for complex values)
  - `resources`, `livenessProbe`, `readinessProbe`
  - `hostPath: { ... }` (if applicable)
  - `waitForDb: true|false` (if applicable)

Example skeleton:

```yaml
secrets:
  postgresPassword: "your-super-secret-and-long-postgres-password"
  jwtSecret: "your-super-secret-jwt-token-with-at-least-32-characters-long"
  anonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
  serviceRoleKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
  dashboardPassword: "this_password_is_insecure_and_should_be_updated"
  secretKeyBase: "your-secret-key-base-64-chars-minimum"
  vaultEncKey: "your-encryption-key-32-chars-min"

global:
  hostPath:
    root: /mnt/ebs_postgres_data/supabase/volumes
  ingressClassName: nginx

ingress:
  kong:
    host: db.bluestone.systems

postgres:
  enabled: true
  image: { repository: supabase/postgres, tag: 15.8.1.060, pullPolicy: IfNotPresent }
  service: { port: 5432 }
  env:
    POSTGRES_DB: postgres
    POSTGRES_USER: postgres
    POSTGRES_PASSWORD: "{{ .Values.secrets.postgresPassword }}"
    JWT_SECRET: "{{ .Values.secrets.jwtSecret }}"
    JWT_EXP: "3600"
  hostPath:
    data: "/mnt/ebs_postgres_data/supabase/volumes/db/data"
    config: "/mnt/ebs_postgres_data/supabase/volumes/db/config"
  command:
    - postgres
    - "-c"
    - "config_file=/etc/postgresql/postgresql.conf"
    - "-c"
    - "log_min_messages=fatal"

auth:
  enabled: true
  image: { repository: supabase/gotrue, tag: v2.177.0, pullPolicy: IfNotPresent }
  service: { port: 9999 }
  env:
    API_EXTERNAL_URL: https://db.bluestone.systems
    GOTRUE_DB_DRIVER: postgres
    GOTRUE_DB_DATABASE_URL: "{{ include \"supabase.auth.databaseUrl\" . }}"
    GOTRUE_JWT_SECRET: "{{ .Values.secrets.jwtSecret }}"
  waitForDb: true

rest:
  enabled: true
  image: { repository: postgrest/postgrest, tag: v12.2.12, pullPolicy: IfNotPresent }
  service: { port: 3000 }
  env:
    PGRST_DB_SCHEMAS: public,storage,graphql_public
    PGRST_DB_URI: "{{ include \"supabase.rest.databaseUri\" . }}"
    PGRST_JWT_SECRET: "{{ .Values.secrets.jwtSecret }}"
  command: [ "postgrest" ]
  waitForDb: true
```

Complex environment variables like database URLs are built using Helm template helper functions that reference values from the `secrets` section.

## Templates (supabase/templates)

- `_helpers.tpl`: contains shared labels, env helpers, EBS check partial, and wait-for-db partial.
- `deployment-*.yaml`: one Deployment template per component (see list above). Each Deployment:
  - Uses the EBS mount check initContainer when hostPath volumes are mounted
  - Mounts hostPath paths under `/mnt/ebs_postgres_data/supabase/volumes` as needed
  - Optionally includes the wait-for-db initContainer for DB-dependent components
- `service-*.yaml`: one Service template per component with selectors including `app.kubernetes.io/component`.
- `deployment-debug.yaml`: optional always-running BusyBox for debugging (enabled via `.Values.debug.enabled`).
- `ingress.yaml`: emits both Ingress objects (Kong and Studio) with `ingressClassName: nginx` and no TLS blocks.

Legacy compatibility:
- The previous monolithic `deployment.yaml` and consolidated `service.yaml` are retained only for reference and can be guarded behind `.Values.legacy.monolithic.enabled` (disabled by default) or removed.

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

1) Update `_helpers.tpl` with partials for EBS check and wait-for-db.
2) Add/align `values.yaml` structure per above (single source of truth for all components).
3) Implement one `deployment-*.yaml` per component; add hostPath mounts and initContainers where needed; include wait-for-db where applicable.
4) Implement one `service-*.yaml` per component; ensure selectors include `app.kubernetes.io/component`.
5) Keep `ingress.yaml` for Kong and Studio (nginx class, no TLS).
6) Add probes and resource defaults; review securityContext/fsGroup for hostPath write access.
7) Optionally add `deployment-debug.yaml` and gate with `.Values.debug.enabled`.
8) README updates for preparing host directories and sentinel file.

Validation:
- Render templates with Helm to verify resources and selectors.
- Deploy to a test namespace and verify inter-service DNS (e.g., `rest`, `postgres`).

## Notes

- We’ll avoid creating Kubernetes Secrets/ConfigMaps per your preference; credentials live in values only.
- No TLS blocks are emitted in Ingress; nginx fake cert + Cloudflare handles TLS.
- Subdomain `db` will not be used for any public endpoint.
