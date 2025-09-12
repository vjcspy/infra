import os
import json
import time
from datetime import datetime, timezone
import urllib.request
import urllib.error

import boto3


ec2 = boto3.client("ec2")
dynamodb = boto3.resource("dynamodb")


HEALTHCHECK_TIMEOUT_SECONDS = int(os.environ.get("HEALTHCHECK_TIMEOUT_SECONDS", "5"))
UNHEALTHY_RESTART_AFTER_SECONDS = int(
    os.environ.get("UNHEALTHY_RESTART_AFTER_SECONDS", str(13 * 60))
)

SLACK_POST_URL = os.environ.get(
    "SLACK_POST_URL", "https://slack.bluestone.systems/slack/post-message"
)
SLACK_TOKEN = os.environ.get("SLACK_TOKEN")
SLACK_CHANNEL = os.environ.get("SLACK_CHANNEL", "general-meta-bot-channel")

# Feature flag (stored in DynamoDB) configuration
DDB_FLAG_ITEM_ID = os.environ.get(
    "DDB_FLAG_ITEM_ID", "feature:healthcheck-enabled"
)
HEALTHCHECK_NOTIFY_WHEN_DISABLED = os.environ.get(
    "HEALTHCHECK_NOTIFY_WHEN_DISABLED", "false"
).lower() in {"1", "true", "yes"}
DISABLED_STATUS_STRING = os.environ.get(
    "HEALTHCHECK_DISABLED_STATUS", "disabled"
)

# Secondary healthcheck configuration (does not impact reboot logic)
SECONDARY_HEALTHCHECK_URL = os.environ.get(
    "SECONDARY_HEALTHCHECK_URL", "https://jhttp.bluestone.systems/q/health/live"
)
SECONDARY_HEALTHCHECK_ENABLED = os.environ.get(
    "SECONDARY_HEALTHCHECK_ENABLED", "true"
).lower() in {"1", "true", "yes"}


def _now_epoch() -> int:
    return int(time.time())


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _check_health(url: str) -> tuple[bool, int | None]:
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=HEALTHCHECK_TIMEOUT_SECONDS) as resp:
            status = resp.getcode()
            is_healthy = 200 <= status < 300
            return is_healthy, status
    except Exception as e:
        print(f"Healthcheck error: {e}")
        return False, None


def _post_slack(text: str) -> None:
    if not SLACK_TOKEN:
        # Token not configured; skip
        print("Slack token not configured; skipping Slack notification")
        return
    try:
        payload = {
            "token": SLACK_TOKEN,
            "payload": {
                "channel_name": SLACK_CHANNEL,
                "messageOptions": {
                    "text": text,
                },
            },
        }
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            SLACK_POST_URL,
            data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=HEALTHCHECK_TIMEOUT_SECONDS) as resp:
            print(f"Slack post status={resp.getcode()}")
    except Exception as e:
        print(f"Slack post error: {e}")


def _get_item(table_name: str, item_id: str) -> dict | None:
    table = dynamodb.Table(table_name)
    try:
        res = table.get_item(Key={"id": item_id})
        return res.get("Item")
    except Exception as e:
        print(f"DynamoDB get_item error: {e}")
        return None


def _put_item(table_name: str, item: dict) -> None:
    table = dynamodb.Table(table_name)
    try:
        table.put_item(Item=item)
    except Exception as e:
        print(f"DynamoDB put_item error: {e}")


def _put_healthy(table_name: str, item_id: str) -> int:
    table = dynamodb.Table(table_name)
    now_epoch = _now_epoch()
    now_iso = _now_iso()
    # PutItem replaces the entire item; we intentionally omit firstSeenUnhealthyAtEpoch when healthy
    table.put_item(
        Item={
            "id": item_id,
            "lastHealthyAtEpoch": now_epoch,
            "lastHealthyAtIso": now_iso,
            "lastStatus": "healthy",
            "updatedAtIso": now_iso,
        }
    )
    return now_epoch


def _mark_unhealthy_reference(table_name: str, item_id: str) -> int:
    """Ensure an 'unhealthy reference' timestamp exists; return the firstSeenUnhealthyAtEpoch.

    We don't misuse lastHealthyAt*; instead, we track first time we've noticed unhealthy when
    a healthy timestamp doesn't exist yet, to avoid immediate reboot thrash.
    """
    table = dynamodb.Table(table_name)
    now_epoch = _now_epoch()
    now_iso = _now_iso()
    try:
        res = table.update_item(
            Key={"id": item_id},
            UpdateExpression=(
                "SET firstSeenUnhealthyAtEpoch = if_not_exists(firstSeenUnhealthyAtEpoch, :now), "
                "lastStatus = :status, updatedAtIso = :iso"
            ),
            ExpressionAttributeValues={
                ":now": now_epoch,
                ":status": "unhealthy",
                ":iso": now_iso,
            },
            ReturnValues="ALL_NEW",
        )
        item = res.get("Attributes", {})
        return int(item.get("firstSeenUnhealthyAtEpoch", now_epoch))
    except Exception as e:
        print(f"DynamoDB update_item error: {e}")
        return now_epoch


def _run_secondary_healthcheck(url: str | None) -> dict:
    """Run the secondary healthcheck and post to Slack if it's unhealthy.

    This does not influence the main health/restart decision; it's fire-and-forget notify.

    Returns a small result dict for observability.
    """
    if not SECONDARY_HEALTHCHECK_ENABLED:
        return {"enabled": False, "skipped": True}
    if not url:
        return {"enabled": True, "skipped": True, "reason": "no_url"}

    healthy, status = _check_health(url)
    if healthy:
        return {"enabled": True, "healthy": True, "status": status}

    # Unhealthy -> notify via Slack
    _post_slack(
        f"healthcheck unhealthy: {url} status={status}. Monitoring only; no reboot action."
    )
    return {"enabled": True, "healthy": False, "status": status}


def _reboot_spot_fleet_instances(spot_fleet_request_id: str) -> tuple[bool, list[str]]:
    try:
        resp = ec2.describe_spot_fleet_instances(
            SpotFleetRequestId=spot_fleet_request_id
        )
        ids = [i["InstanceId"] for i in resp.get("ActiveInstances", [])]
        if not ids:
            print("No active instances found for the Spot Fleet Request.")
            return False, []

        print(f"Rebooting instances: {ids}")
        ec2.reboot_instances(InstanceIds=ids)
        return True, ids
    except Exception as e:
        print(f"EC2 reboot error: {e}")
        return False, []


def _is_healthcheck_disabled(table_name: str, flag_item_id: str) -> bool:
    """Return True if the healthcheck is disabled via feature flag.

    Convention: Item {"id": flag_item_id, "enabled": <bool>}.
    Absence of the item OR enabled=True => healthcheck active.
    enabled=False => disabled.
    """
    item = _get_item(table_name, flag_item_id)
    if not item:
        return False  # Default enabled
    enabled = item.get("enabled")
    # Treat any value explicitly False (bool False or string 'false') as disabled
    if isinstance(enabled, str):
        enabled_norm = enabled.lower() in {"1", "true", "yes"}
    else:
        enabled_norm = bool(enabled) if enabled is not None else True
    return not enabled_norm


def run(event, context):
    url = os.environ.get(
        "HEALTHCHECK_URL", "https://whoami.bluestone.systems"
    )
    table_name = os.environ.get("DDB_TABLE_NAME", "common")
    item_id = os.environ.get("DDB_ITEM_ID", "health:jhttp-live")
    sfr_id = os.environ["SPOT_FLEET_REQUEST_ID"]
    flag_item_id = DDB_FLAG_ITEM_ID

    # Respect feature flag
    if _is_healthcheck_disabled(table_name, flag_item_id):
        now_iso = _now_iso()
        print("Healthcheck disabled via feature flag; skipping logic.")
        # Optionally record a disabled heartbeat so operators can see it's alive but disabled
        _put_item(
            table_name,
            {
                "id": item_id,
                "lastStatus": DISABLED_STATUS_STRING,
                "updatedAtIso": now_iso,
            },
        )
        if HEALTHCHECK_NOTIFY_WHEN_DISABLED:
            _post_slack(
                f"Healthcheck disabled (flag item '{flag_item_id}'). Skipping execution at {now_iso}."
            )
        return {
            "healthy": None,
            "action": "skipped",
            "reason": "disabled",
            "flagItemId": flag_item_id,
        }

    try:
        # Run secondary healthcheck in addition to the main one; notify only when unhealthy
        _run_secondary_healthcheck(SECONDARY_HEALTHCHECK_URL)
    except Exception:
        pass  # IGNORE

    healthy, status = _check_health(url)

    if healthy:
        epoch = _put_healthy(table_name, item_id)
        print(f"Healthy (status={status}). Updated lastHealthyAtEpoch={epoch}")
        return {"healthy": True, "status": status, "updated": epoch}

    # Unhealthy path: decide whether to reboot based on last healthy time or first seen unhealthy
    item = _get_item(table_name, item_id) or {}
    last_healthy_epoch = item.get("lastHealthyAtEpoch")
    now = _now_epoch()

    if last_healthy_epoch is not None:
        try:
            age = now - int(last_healthy_epoch)
        except Exception:
            age = None
    else:
        age = None

    print(
        f"Unhealthy (status={status}). lastHealthyAtEpoch={last_healthy_epoch}, age={age} seconds"
    )

    if age is None:
        # No recorded healthy time yet; notify and wait until we have a healthy baseline
        _post_slack(
            "Healthcheck: Unhealthy detected but no last healthy timestamp yet; monitoring and will not reboot until a healthy baseline is recorded."
        )
        return {
            "healthy": False,
            "action": "none",
            "reason": "no_last_healthy_timestamp",
        }

    # We have a last healthy timestamp; compare against threshold
    if age is not None and age > UNHEALTHY_RESTART_AFTER_SECONDS:
        ok, ids = _reboot_spot_fleet_instances(sfr_id)
        _post_slack(
            f"Healthcheck: Unhealthy for {age}s (> {UNHEALTHY_RESTART_AFTER_SECONDS}s). Rebooting instances: {ids}"
        )
        action = "rebooted" if ok else "no_instances"
        return {
            "healthy": False,
            "action": action,
            "instanceIds": ids,
            "age": age,
        }

    # Always notify on unhealthy when below restart threshold
    _post_slack(
        f"Healthcheck: Unhealthy for {age}s (< {UNHEALTHY_RESTART_AFTER_SECONDS}s). Monitoring."
    )
    
    return {"healthy": False, "action": "none", "age": age}