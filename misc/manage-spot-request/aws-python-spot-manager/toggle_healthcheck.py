import json
import os
from datetime import datetime, timezone

import boto3

dynamodb = boto3.resource("dynamodb")

# Environment configuration
TABLE_NAME = os.environ.get("DDB_TABLE_NAME", "common")
FLAG_ITEM_ID = os.environ.get("DDB_FLAG_ITEM_ID", "feature:healthcheck-enabled")
DEFAULT_ENABLED = os.environ.get("HEALTHCHECK_DEFAULT_ENABLED", "true").lower() in {"1", "true", "yes"}


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _response(status: int, body: dict):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def _get_flag(table, item_id: str) -> bool:
    try:
        res = table.get_item(Key={"id": item_id})
        item = res.get("Item")
        if not item:
            return DEFAULT_ENABLED
        enabled = item.get("enabled")
        if isinstance(enabled, str):
            return enabled.lower() in {"1", "true", "yes"}
        if enabled is None:
            return DEFAULT_ENABLED
        return bool(enabled)
    except Exception as e:
        print(f"Error getting flag: {e}")
        return DEFAULT_ENABLED


def _set_flag(table, item_id: str, enabled: bool) -> bool:
    try:
        table.put_item(
            Item={
                "id": item_id,
                "enabled": enabled,
                "updatedAtIso": _now_iso(),
                "type": "feature-flag",
            }
        )
        return True
    except Exception as e:
        print(f"Error setting flag: {e}")
        return False


def handler(event, context):
    """Lambda handler to get or update the healthcheck enable flag.

    Supported operations:
    - GET  (no body): return current flag state
    - POST {"enabled": <bool>} : update flag
    - Any other method: 405
    """
    table = dynamodb.Table(TABLE_NAME)
    # Support both REST API ("httpMethod") and HTTP API v2 (requestContext.http.method)
    rc = event.get("requestContext") or {}
    http_block = rc.get("http") or {}
    method = (
        event.get("httpMethod")
        or rc.get("httpMethod")  # legacy / REST
        or http_block.get("method")  # HTTP API v2
        or "GET"
    ).upper()
    print(f"Received {method} request")
    if method == "GET":
        enabled = _get_flag(table, FLAG_ITEM_ID)
        return _response(200, {"enabled": enabled, "flagItemId": FLAG_ITEM_ID})

    if method == "POST":
        body_raw = event.get("body")
        try:
            body = json.loads(body_raw) if body_raw else {}
        except json.JSONDecodeError:
            return _response(400, {"error": "Invalid JSON body"})

        if "enabled" not in body:
            return _response(400, {"error": "Missing 'enabled' field"})
    
        enabled_val = bool(body["enabled"])
        print(f"Setting flag {FLAG_ITEM_ID} to {enabled_val}")
        ok = _set_flag(table, FLAG_ITEM_ID, enabled_val)
        if not ok:
            return _response(500, {"error": "Failed to persist flag"})
        return _response(200, {"enabled": enabled_val, "flagItemId": FLAG_ITEM_ID})

    return _response(405, {"error": "Method not allowed"})
