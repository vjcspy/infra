#!/usr/bin/env bash
# Runs inside the dieuvang-magento-build Job as the SOLE Magento process (the runtime Deployment is at 0 replicas).
# Install mode when app/etc/env.php is absent, upgrade mode otherwise. Never echoes a secret; no `set -x`.
set -euo pipefail
cd /var/www/html

peak() {
  if [ -r /sys/fs/cgroup/memory.peak ]; then
    echo "build memory.peak=$(cat /sys/fs/cgroup/memory.peak) bytes"
  fi
}
trap peak EXIT

mage() { php -d memory_limit=-1 bin/magento "$@"; }

# 1. Fail-closed maintenance flag (the file `maintenance:enable` writes). Stays set if any later step fails.
mkdir -p var
touch var/.maintenance.flag

# 2. Dependencies. Empty generated/ BEFORE the dump: an optimized classmap that lists previously generated classes
# breaks the next DI compile once Magento's composer plugin has cleared them ("Failed to open stream ... Proxy.php").
rm -rf generated/code generated/metadata
php -d memory_limit=-1 "$(command -v composer)" install --no-dev --no-interaction --optimize-autoloader

if [ ! -f app/etc/env.php ]; then
  echo "== install mode"
  # 3. Install.
  mage setup:install \
    --db-host=dieuvang-mariadb --db-name=magento --db-user=magento --db-password="$DB_PASSWORD" \
    --search-engine=opensearch --opensearch-host=dieuvang-opensearch --opensearch-port=9200 \
    --cache-backend=redis --cache-backend-redis-server=dieuvang-valkey --cache-backend-redis-db=0 \
    --page-cache=redis --page-cache-redis-server=dieuvang-valkey --page-cache-redis-db=1 \
    --session-save=files \
    --base-url="https://${BASE_HOST}/" --base-url-secure="https://${BASE_HOST}/" \
    --use-secure=1 --use-secure-admin=1 --use-rewrites=1 \
    --backend-frontname="$ADMIN_FRONTNAME" \
    --admin-user="$ADMIN_USER" --admin-password="$ADMIN_PASSWORD" --admin-email="$ADMIN_EMAIL" \
    --admin-firstname=Dieu --admin-lastname=Vang \
    --language="$SHOP_LANGUAGE" --currency="$SHOP_CURRENCY" --timezone="$SHOP_TIMEZONE"
  mage config:set web/secure/offloader_header X-Forwarded-Proto
  # 5. Production mode (compiles DI, deploys static content for the configured locales).
  mage deploy:mode:set production
else
  echo "== upgrade mode"
  # 4. Upgrade. `composer install` empties generated/, so compile first, then upgrade with --keep-generated.
  mage setup:di:compile
  mage setup:upgrade --keep-generated
  rm -rf pub/static/frontend pub/static/adminhtml var/view_preprocessed
  mage setup:static-content:deploy -f en_US vi_VN
fi

mage indexer:set-mode realtime
mage indexer:reindex

# 6. Seed (install mode only) inside the same sole-writer window.
if [ ! -f var/.dieuvang-seeded ] && [ "${SEED_ON_INSTALL:-0}" = "1" ]; then
  mage dieuvang:seed
  mage catalog:images:resize
  touch var/.dieuvang-seeded
fi

# 7. Last command: reached only when every step succeeded.
mage cache:flush
mage maintenance:disable
