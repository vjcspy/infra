#!/usr/bin/env bash
# Operator script for the dieuvang chart. Runs ON the k3s host from the infra clone (not on a laptop).
#
#   deploy.sh bootstrap                 first install (idempotent)
#   deploy.sh magento [ref]             rebuild + redeploy Magento (default: origin/main)
#   deploy.sh storefront [ref]          build a new immutable storefront release and publish it
#   deploy.sh seed                      re-run dieuvang:seed in the live Magento pod
#   deploy.sh rollback-storefront       swap `current` and PREVIOUS
#   deploy.sh reap                      clean up after an interrupted run
#   deploy.sh status                    state, jobs, pods, versions, capacity (no lock)
#
# Full procedure: resources/workspaces/k/dv/_guides/__runbooks/261003-dieuvang-k3s-deploy.md
# Secrets are never echoed and never put on a command line; they live in k8s Secrets only.
set -euo pipefail

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
NS=dieuvang
REL=dieuvang
D=/mnt/existing_ebs_volume/dieuvang
DB_DIR=/mnt/ebs_postgres_data/docker_data/mariadb/dieuvang
INFRA=${DV_INFRA_DIR:-/home/ec2-user/infra}
CHART=$INFRA/k8s/app/dieuvang
MAGENTO_REPO=git@github.com:vjcspy/dv-magento.git
STOREFRONT_REPO=git@github.com:vjcspy/dv-storefront.git

MEM_MARGIN_MI=${DV_MEM_MARGIN_MI:-1024}
DISK_FLOOR_PCT=${DV_DISK_FLOOR_PCT:-15}
EST_BOOTSTRAP_GI=${DV_EST_BOOTSTRAP_GI:-11}
EST_BUILD_GI=${DV_EST_BUILD_GI:-1.5}
MAGENTO_JOB_MEM_MI=3072
STOREFRONT_JOB_MEM_MI=2560

INFLIGHT=""        # magento | storefront while an operation owns the state file
CURRENT_JOB=""
RELEASE_ID=""
PREFLIGHT_DONE=0

# kubectl/helm run with fd 9 (the lock) closed so a killed script does not leave the lock held by a child.
kc() { kubectl -n "$NS" "$@" 9>&-; }
hl() { helm "$@" 9>&-; }

log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- state files
state_get() { cat "$D/state/$1" 2>/dev/null || true; }
state_set() { # name line...
  local name=$1
  shift
  mkdir -p "$D/state"
  printf '%s\n' "$*" >"$D/state/$name.tmp"
  mv -f "$D/state/$name.tmp" "$D/state/$name"
}

# ----------------------------------------------------------------------- lock
acquire_lock() {
  mkdir -p "$D/state" "$D/logs"
  exec 9>"$D/.deploy.lock"
  flock -n 9 || die "another deploy.sh run holds $D/.deploy.lock"
  LOG="$D/logs/$(date -u +%Y%m%d%H%M%S)-${SUBCMD}.log"
  # tee must not inherit the lock fd, or a killed script would leave the lock held by its logger.
  exec > >(tee -a "$LOG" 9>&-) 2>&1
  log "log: $LOG"
}

# ------------------------------------------------------------------- helpers
pods_gone() { # label selector
  local i
  for i in $(seq 1 90); do
    if [ -z "$(kc get pod -l "$1" -o name 2>/dev/null)" ]; then return 0; fi
    sleep 2 9>&-
  done
  return 1
}

nonterminal_jobs() {
  kc get ns "$NS" >/dev/null 2>&1 || return 0
  kc get jobs -l app.kubernetes.io/component=build -o json |
    jq -r '.items[] | select(([.status.conditions[]? | select((.type=="Complete" or .type=="Failed") and .status=="True")] | length)==0) | .metadata.name'
}

gate() {
  local j m s bad=0
  for j in $(nonterminal_jobs); do
    bad=1
    echo "nonterminal build Job: $j (pods: $(kc get pod -l "job-name=$j" -o jsonpath='{.items[*].status.phase}'))"
  done
  m=$(state_get magento)
  s=$(state_get storefront)
  case "$m" in building*) bad=1; echo "state/magento: $m" ;; esac
  case "$s" in building*) bad=1; echo "state/storefront: $s" ;; esac
  [ "$bad" = 0 ] || die "a build may still own the stacks - run: deploy.sh reap"
}

preflight() { # job_mem_mi est_gi
  [ "$PREFLIGHT_DONE" = 1 ] && return 0
  local need_mi=$(($1 + MEM_MARGIN_MI)) avail_kb avail_mi avail_b size_b
  avail_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
  avail_mi=$((avail_kb / 1024))
  read -r avail_b size_b < <(df -B1 --output=avail,size /mnt/existing_ebs_volume | tail -1)
  log "preflight: MemAvailable=${avail_mi}Mi need>=${need_mi}Mi; app volume avail=$((avail_b / 1048576))Mi size=$((size_b / 1048576))Mi estimate=${2}Gi floor=${DISK_FLOOR_PCT}%"
  [ "$avail_mi" -ge "$need_mi" ] || die "preflight: MemAvailable ${avail_mi}Mi < ${need_mi}Mi (nothing changed)"
  awk -v a="$avail_b" -v s="$size_b" -v e="$2" -v f="$DISK_FLOOR_PCT" \
    'BEGIN { exit !((a - e * 1073741824) >= s * f / 100) }' ||
    die "preflight: app volume would drop below ${DISK_FLOOR_PCT}% free (nothing changed)"
  return 0
}

frontname() { kc get secret dieuvang-magento-admin -o jsonpath='{.data.frontName}' | base64 -d; }

# The ONLY path replicas reach Helm. M=1 only when state/magento is `ok` (or explicit M_OVERRIDE), S=1 only when a
# published release exists. The adminFrontName goes through a process-substitution values file, never argv.
helm_upgrade() {
  local m=0 s=0 fn
  case "$(state_get magento)" in ok\ *) m=1 ;; esac
  [ -n "${M_OVERRIDE:-}" ] && m=$M_OVERRIDE
  [ -d "$D/storefront/current/" ] && s=1
  fn=$(frontname) || die "Secret dieuvang-magento-admin is missing"
  [ -n "$fn" ] || die "empty frontName"
  log "helm upgrade: magento.replicas=$m storefront.replicas=$s"
  hl upgrade --install "$REL" "$CHART" -n "$NS" --create-namespace \
    --set "magento.replicas=$m" --set "storefront.replicas=$s" \
    --values <(printf 'magento:\n  adminFrontName: %s\n' "$fn") >/dev/null
}

helm_prelude() {
  git -C "$INFRA" pull --ff-only
  helm_upgrade
}

wait_infra_ready() {
  local d
  for d in mariadb opensearch valkey; do
    kc rollout status "deploy/dieuvang-$d" --timeout=600s
  done
}

wait_job() { # job -> 0 complete, 1 failed/timeout
  local job=$1 i c f
  for i in $(seq 1 450); do
    c=$(kc get job "$job" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || true)
    f=$(kc get job "$job" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || true)
    [ "$c" = True ] && return 0
    [ "$f" = True ] && return 1
    if [ $((i % 6)) = 0 ]; then
      log "job $job running: $(kc logs "job/$job" --tail=1 2>/dev/null | cut -c1-160 || true)"
    fi
    sleep 10 9>&-
  done
  return 1
}

delete_job() { # job
  kc delete job "$1" --cascade=foreground --wait --ignore-not-found >/dev/null 2>&1 || true
  pods_gone "job-name=$1" || log "warning: pods of $1 still present"
}

run_job() { # cronjob job
  CURRENT_JOB=$2
  kc create job --from="cronjob/$1" "$2"
  if wait_job "$2"; then
    kc logs "job/$2" >"$D/logs/$2.job.log" 2>&1 || true
    kc logs "job/$2" --tail=12 || true
    CURRENT_JOB=""
    return 0
  fi
  kc logs "job/$2" >"$D/logs/$2.job.log" 2>&1 || true
  log "---- last 40 lines of $2 (full log: $D/logs/$2.job.log)"
  kc logs "job/$2" --tail=40 || true
  delete_job "$2"
  CURRENT_JOB=""
  return 1
}

# Best-effort cleanup on INT/TERM/EXIT. SIGKILL / SSH loss / host loss skip it: gate + `reap` cover those.
on_exit() {
  local rc=$?
  trap - EXIT INT TERM
  if [ -n "$INFLIGHT" ] && [[ "$(state_get "$INFLIGHT")" == building* ]]; then
    log "interrupted (rc=$rc): cleaning up $INFLIGHT"
    [ -n "$CURRENT_JOB" ] && delete_job "$CURRENT_JOB"
    if [ "$INFLIGHT" = storefront ] && [ -n "$RELEASE_ID" ]; then
      remove_release "$RELEASE_ID"
      state_set storefront "failed $RELEASE_ID interrupted"
    elif [ "$INFLIGHT" = magento ]; then
      state_set magento "failed $(awk '{print $2}' <<<"$(state_get magento)") interrupted"
      helm_upgrade || true
    fi
  fi
  exit "$rc"
}

remove_release() { # id : only ever an unpublished release (never current / PREVIOUS)
  local id=$1
  [ -n "$id" ] || return 0
  [ "$id" = "$(basename "$(readlink "$D/storefront/current" 2>/dev/null || echo none)")" ] && return 0
  [ "$id" = "$(cat "$D/storefront/PREVIOUS" 2>/dev/null || echo none)" ] && return 0
  git -C "$D/storefront/repo.git" worktree remove --force "$D/storefront/releases/$id" 2>/dev/null || rm -rf "${D:?}/storefront/releases/$id"
  git -C "$D/storefront/repo.git" worktree prune
}

# ------------------------------------------------------------------- bootstrap
ensure_dirs() {
  install -d -m 755 "$D" "$D/state" "$D/logs" "$D/opensearch" "$D/storefront" "$D/storefront/releases" \
    "$D/cache" "$D/cache/composer" "$D/cache/corepack" "$D/cache/corepack-bin"
  if [ ! -d "$DB_DIR" ]; then
    sudo install -d -o 1000 -g 1000 "$DB_DIR"
  fi
}

ensure_repos() {
  if [ ! -d "$D/magento/.git" ]; then
    git clone "$MAGENTO_REPO" "$D/magento"
  fi
  if [ ! -d "$D/storefront/repo.git" ]; then
    git clone --mirror "$STOREFRONT_REPO" "$D/storefront/repo.git"
  fi
}

rand() { openssl rand -hex "$1"; }

ensure_secrets() {
  kc get secret dieuvang-composer-auth >/dev/null 2>&1 ||
    die "Secret dieuvang-composer-auth is missing - create it from the laptop first (runbook, step C2)"
  if ! kc get secret dieuvang-mariadb >/dev/null 2>&1; then
    printf 'rootPassword=%s\npassword=%s\n' "$(rand 24)" "$(rand 24)" |
      kc create secret generic dieuvang-mariadb --from-env-file=/dev/stdin >/dev/null
    log "created Secret dieuvang-mariadb"
  fi
  if ! kc get secret dieuvang-magento-admin >/dev/null 2>&1; then
    printf 'username=dv_admin\npassword=Dv%s9\nemail=admin@dieuvang.bluestone.systems\nfrontName=admin_%s\n' "$(rand 16)" "$(rand 6)" |
      kc create secret generic dieuvang-magento-admin --from-env-file=/dev/stdin >/dev/null
    log "created Secret dieuvang-magento-admin"
  fi
}

# --------------------------------------------------------------------- magento
do_magento() { # ref
  local ref=${1:-origin/main} sha job
  git -C "$D/magento" fetch origin --prune
  sha=$(git -C "$D/magento" rev-parse --verify "${ref}^{commit}") || die "cannot resolve ref $ref"
  preflight "$MAGENTO_JOB_MEM_MI" "$EST_BUILD_GI"
  job="dieuvang-magento-build-$(date -u +%Y%m%d%H%M%S)"
  state_set magento "building $sha $job"
  INFLIGHT=magento
  helm_prelude # state=building -> M=0
  wait_infra_ready
  pods_gone "app.kubernetes.io/component=magento" || die "magento pods did not terminate"
  git -C "$D/magento" rev-parse HEAD >"$D/magento.prev" 2>/dev/null || true
  mkdir -p "$D/magento/src/var"
  touch "$D/magento/src/var/.maintenance.flag"
  git -C "$D/magento" checkout --detach "$sha"
  if ! run_job dieuvang-magento-build "$job"; then
    state_set magento "failed $sha build"
    INFLIGHT=""
    helm_upgrade || true
    die "magento build failed (state: failed $sha build); Magento stays at 0 replicas"
  fi
  if ! M_OVERRIDE=1 helm_upgrade; then
    state_set magento "failed $sha helm"
    INFLIGHT=""
    helm_upgrade || true
    die "helm upgrade failed after build"
  fi
  local i ok=0
  for i in $(seq 1 60); do
    if kc exec deploy/dieuvang-magento -c nginx -- nginx -t >/dev/null 2>&1; then ok=1; break; fi
    sleep 5 9>&-
  done
  if [ "$ok" != 1 ] || ! kc rollout status deploy/dieuvang-magento --timeout=600s; then
    state_set magento "failed $sha rollout"
    INFLIGHT=""
    helm_upgrade || true
    die "magento rollout failed (nginx -t / readiness)"
  fi
  kc create secret generic dieuvang-magento-env --from-file=env.php="$D/magento/src/app/etc/env.php" \
    --dry-run=client -o yaml | kc apply -f - >/dev/null
  state_set magento "ok $sha"
  INFLIGHT=""
  log "magento ok $sha"
}

# ------------------------------------------------------------------ storefront
do_storefront() { # ref
  local ref=${1:-origin/main} sha id job prev=""
  ref=${ref#origin/}
  [[ "$ref" == refs/* || "$ref" =~ ^[0-9a-f]{7,40}$ ]] || ref="refs/heads/$ref"
  git -C "$D/storefront/repo.git" fetch --prune origin
  sha=$(git -C "$D/storefront/repo.git" rev-parse --verify "${ref}^{commit}") || die "cannot resolve ref $ref"
  preflight "$STOREFRONT_JOB_MEM_MI" "$EST_BUILD_GI"
  id="$(date -u +%Y%m%d%H%M%S)-${sha:0:12}"
  job="dieuvang-storefront-build-${id%%-*}"
  state_set storefront "building $id $job"
  INFLIGHT=storefront
  RELEASE_ID=$id
  helm_prelude
  git -C "$D/storefront/repo.git" worktree add --detach "$D/storefront/releases/$id" "$sha" >/dev/null
  printf '%s\n' "$id" >"$D/storefront/NEXT"
  if ! run_job dieuvang-storefront-build "$job"; then
    remove_release "$id"
    state_set storefront "failed $id build"
    INFLIGHT=""
    die "storefront build failed; current untouched"
  fi
  if [ -L "$D/storefront/current" ]; then
    prev=$(basename "$(readlink "$D/storefront/current")")
    printf '%s\n' "$prev" >"$D/storefront/PREVIOUS"
  fi
  ln -sfn "releases/$id" "$D/storefront/current.tmp"
  mv -T "$D/storefront/current.tmp" "$D/storefront/current"
  if [ -z "$prev" ]; then
    helm_upgrade
  else
    kc rollout restart deploy/dieuvang-storefront >/dev/null
  fi
  if ! kc rollout status deploy/dieuvang-storefront --timeout=300s; then
    if [ -n "$prev" ]; then
      ln -sfn "releases/$prev" "$D/storefront/current.tmp"
      mv -T "$D/storefront/current.tmp" "$D/storefront/current"
      kc rollout restart deploy/dieuvang-storefront >/dev/null
      kc rollout status deploy/dieuvang-storefront --timeout=300s || true
    fi
    state_set storefront "failed $id rollout"
    INFLIGHT=""
    die "storefront rollout failed; current re-pointed to ${prev:-<none>}"
  fi
  # Prune: keep only current + PREVIOUS (the gate guarantees no build Job is running).
  local d name
  for d in "$D"/storefront/releases/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    [ "$name" = "$id" ] && continue
    [ "$name" = "$prev" ] && continue
    remove_release "$name"
  done
  git -C "$D/storefront/repo.git" worktree prune
  state_set storefront "ok $id"
  INFLIGHT=""
  log "storefront ok $id"
}

# ------------------------------------------------------------------ subcommands
cmd_bootstrap() {
  acquire_lock
  gate
  preflight "$MAGENTO_JOB_MEM_MI" "$EST_BOOTSTRAP_GI"
  PREFLIGHT_DONE=1
  ensure_dirs
  ensure_repos
  kc get ns "$NS" >/dev/null 2>&1 || kubectl create namespace "$NS" 9>&-
  ensure_secrets
  do_magento "${1:-origin/main}"
  do_storefront "${2:-origin/main}"
  log "bootstrap done"
}

cmd_magento() {
  acquire_lock
  gate
  do_magento "${1:-origin/main}"
}

cmd_storefront() {
  acquire_lock
  gate
  do_storefront "${1:-origin/main}"
}

cmd_seed() {
  acquire_lock
  gate
  [[ "$(state_get magento)" == ok\ * ]] || die "state/magento is not ok"
  kc exec deploy/dieuvang-magento -c php-fpm -- php -d memory_limit=-1 bin/magento dieuvang:seed
  kc exec deploy/dieuvang-magento -c php-fpm -- php -d memory_limit=-1 bin/magento catalog:images:resize
}

cmd_rollback_storefront() {
  acquire_lock
  gate
  local cur prev
  cur=$(basename "$(readlink "$D/storefront/current")")
  prev=$(cat "$D/storefront/PREVIOUS" 2>/dev/null || true)
  [ -n "$prev" ] && [ -d "$D/storefront/releases/$prev" ] || die "no PREVIOUS release to roll back to"
  ln -sfn "releases/$prev" "$D/storefront/current.tmp"
  mv -T "$D/storefront/current.tmp" "$D/storefront/current"
  printf '%s\n' "$cur" >"$D/storefront/PREVIOUS"
  kc rollout restart deploy/dieuvang-storefront >/dev/null
  kc rollout status deploy/dieuvang-storefront --timeout=300s
  state_set storefront "ok $prev"
  log "current -> $prev (PREVIOUS -> $cur)"
}

cmd_reap() {
  acquire_lock
  local j m s id
  for j in $(nonterminal_jobs); do
    log "reaping Job $j"
    delete_job "$j"
  done
  m=$(state_get magento)
  case "$m" in building*) state_set magento "failed $(awk '{print $2}' <<<"$m") interrupted" ;; esac
  s=$(state_get storefront)
  case "$s" in
    building*)
      id=$(awk '{print $2}' <<<"$s")
      remove_release "$id"
      state_set storefront "failed $id interrupted"
      ;;
  esac
  helm_upgrade
  log "reap done: magento=$(state_get magento) storefront=$(state_get storefront)"
}

cmd_status() {
  echo "== state"
  echo "magento:    $(state_get magento)"
  echo "storefront: $(state_get storefront)"
  case "$(state_get magento)" in failed*) echo "(Magento at 0 replicas with a failed state is the intentional fail-closed state)" ;; esac
  echo "== nonterminal build Jobs"
  nonterminal_jobs
  echo "== lock"
  if [ ! -e "$D/.deploy.lock" ]; then
    echo "free (never taken)"
  elif (
    exec 8<"$D/.deploy.lock"
    flock -n 8
  ) 2>/dev/null; then echo "free"; else echo "HELD"; fi
  echo "== pods"
  kc get pods -o wide 2>/dev/null || true
  echo "== release pointers"
  echo "current:  $(readlink "$D/storefront/current" 2>/dev/null || echo none)"
  echo "PREVIOUS: $(cat "$D/storefront/PREVIOUS" 2>/dev/null || echo none)"
  echo "magento.prev: $(cat "$D/magento.prev" 2>/dev/null || echo none)"
  echo "magento HEAD: $(git -C "$D/magento" rev-parse HEAD 2>/dev/null || echo none)"
  echo "== capacity"
  awk '/^MemAvailable:/ {printf "MemAvailable: %d MiB\n", $2/1024}' /proc/meminfo
  df -h /mnt/existing_ebs_volume /mnt/ebs_postgres_data
  du -sh "$D" "$DB_DIR" 2>/dev/null || true
}

SUBCMD=${1:-}
shift || true
case "$SUBCMD" in
  bootstrap | magento | storefront | seed | reap | rollback-storefront)
    trap on_exit EXIT
    trap 'exit 130' INT TERM
    case "$SUBCMD" in
      rollback-storefront) cmd_rollback_storefront "$@" ;;
      *) "cmd_$SUBCMD" "$@" ;;
    esac
    ;;
  status) cmd_status ;;
  *) die "usage: deploy.sh bootstrap|magento [ref]|storefront [ref]|seed|rollback-storefront|reap|status" ;;
esac
