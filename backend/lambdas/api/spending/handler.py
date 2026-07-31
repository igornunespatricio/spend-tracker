"""
Spending API Lambda — handles all REST endpoints for spending items and processing jobs.

Routes:
  GET    /api/spending              — list spending items with date range filter
  POST   /api/spending              — create a spending item manually
  DELETE /api/spending/{itemId}     — delete a spending item
  GET    /api/jobs/{jobId}          — get processing job status
  POST   /api/jobs                  — create job + return pre-signed S3 upload URL
  POST   /api/jobs/{jobId}/submit   — enqueue job for processing
  PUT    /api/jobs/{jobId}/confirm  — confirm extracted items, write as SpendingItems
  GET    /api/categories            — list distinct categories for the user
"""
from __future__ import annotations

import json
import logging
import os
import uuid
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any

import boto3
from boto3.dynamodb.conditions import Key

logger = logging.getLogger()
logger.setLevel(logging.INFO)

TABLE_NAME = os.environ["TABLE_NAME"]
PHOTOS_BUCKET = os.environ["PHOTOS_BUCKET"]
PROCESSING_QUEUE_URL = os.environ["PROCESSING_QUEUE_URL"]
REGION = os.environ.get("REGION", "us-east-1")
ALLOWED_MODELS = os.environ.get("ALLOWED_MODELS", "anthropic.claude-3-haiku-20240307-v1:0").split(",")

dynamodb = boto3.resource("dynamodb", region_name=REGION)
table = dynamodb.Table(TABLE_NAME)
s3 = boto3.client("s3", region_name=REGION)
sqs = boto3.client("sqs", region_name=REGION)

CORS_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type,Authorization",
}


def _ok(body: Any, status: int = 200) -> dict:
    return {"statusCode": status, "headers": CORS_HEADERS, "body": json.dumps(body, default=str)}


def _err(message: str, status: int = 400) -> dict:
    return {"statusCode": status, "headers": CORS_HEADERS, "body": json.dumps({"error": message})}


def _user_id(event: dict) -> str:
    """Extract the Cognito sub (user ID) from the JWT claims."""
    try:
        return event["requestContext"]["authorizer"]["jwt"]["claims"]["sub"]
    except (KeyError, TypeError):
        raise PermissionError("Missing or invalid JWT claims")


def handler(event: dict, context: Any) -> dict:
    log_ctx = {"path": event.get("rawPath"), "method": event.get("requestContext", {}).get("http", {}).get("method")}
    logger.info(json.dumps({"msg": "request", **log_ctx}))

    try:
        user_id = _user_id(event)
    except PermissionError as exc:
        return _err(str(exc), 401)

    method = event.get("requestContext", {}).get("http", {}).get("method", "")
    raw_path = event.get("rawPath", "")
    path_params = event.get("pathParameters") or {}

    try:
        # ── Spending items ────────────────────────────────────────────────────
        if raw_path == "/api/spending" and method == "GET":
            return _list_spending(user_id, event.get("queryStringParameters") or {})

        if raw_path == "/api/spending" and method == "POST":
            return _create_spending(user_id, json.loads(event.get("body") or "{}"))

        if raw_path.startswith("/api/spending/") and method == "DELETE":
            return _delete_spending(user_id, path_params.get("itemId", ""))

        # ── Categories ────────────────────────────────────────────────────────
        if raw_path == "/api/categories" and method == "GET":
            return _list_categories(user_id)

        # ── Processing jobs ───────────────────────────────────────────────────
        if raw_path == "/api/jobs" and method == "POST":
            return _create_job(user_id, json.loads(event.get("body") or "{}"))

        if raw_path.endswith("/submit") and method == "POST":
            return _submit_job(user_id, path_params.get("jobId", ""))

        if raw_path.endswith("/confirm") and method == "PUT":
            return _confirm_job(user_id, path_params.get("jobId", ""), json.loads(event.get("body") or "{}"))

        if raw_path.startswith("/api/jobs/") and method == "GET":
            return _get_job(user_id, path_params.get("jobId", ""))

    except Exception as exc:
        logger.error(json.dumps({"msg": "unhandled_error", "error": str(exc)}))
        return _err("Internal server error", 500)

    return _err("Not found", 404)


# ── Spending handlers ─────────────────────────────────────────────────────────

def _list_spending(user_id: str, params: dict) -> dict:
    date_from = params.get("from", "2000-01-01")
    date_to = params.get("to", datetime.now(timezone.utc).strftime("%Y-%m-%d"))

    response = table.query(
        KeyConditionExpression=Key("PK").eq(f"USER#{user_id}") & Key("SK").between(
            f"SPEND#{date_from}", f"SPEND#{date_to}T99:99:99Z"
        )
    )
    return _ok({"items": response.get("Items", [])})


def _create_spending(user_id: str, body: dict) -> dict:
    required = {"amount", "category", "description"}
    missing = required - body.keys()
    if missing:
        return _err(f"Missing required fields: {', '.join(missing)}")

    try:
        amount = Decimal(str(body["amount"]))
    except Exception:
        return _err("Invalid amount value")

    if amount <= 0:
        return _err("Amount must be positive")

    item_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc).isoformat()

    item = {
        "PK": f"USER#{user_id}",
        "SK": f"SPEND#{now}#{item_id}",
        "GSI1PK": body["category"].upper(),
        "GSI1SK": now,
        "itemId": item_id,
        "userId": user_id,
        "amount": amount,
        "category": body["category"].upper(),
        "description": body["description"],
        "location": body.get("location", ""),
        "source": "manual",
        "createdAt": now,
        "updatedAt": now,
    }

    table.put_item(Item=item)
    logger.info(json.dumps({"msg": "spending_created", "userId": user_id, "itemId": item_id}))
    return _ok({"item": item}, 201)


def _delete_spending(user_id: str, item_id: str) -> dict:
    if not item_id:
        return _err("Missing itemId")

    response = table.query(
        KeyConditionExpression=Key("PK").eq(f"USER#{user_id}") & Key("SK").begins_with("SPEND#"),
        FilterExpression="itemId = :id",
        ExpressionAttributeValues={":id": item_id},
        Limit=1,
    )
    items = response.get("Items", [])
    if not items:
        return _err("Item not found", 404)

    table.delete_item(Key={"PK": items[0]["PK"], "SK": items[0]["SK"]})
    return _ok({"deleted": True})


def _list_categories(user_id: str) -> dict:
    response = table.query(
        KeyConditionExpression=Key("PK").eq(f"USER#{user_id}") & Key("SK").begins_with("SPEND#"),
        ProjectionExpression="category",
    )
    categories = list({item["category"] for item in response.get("Items", []) if item.get("category")})
    return _ok({"categories": sorted(categories)})


# ── Job handlers ──────────────────────────────────────────────────────────────

def _create_job(user_id: str, body: dict) -> dict:
    model_id = body.get("modelId", ALLOWED_MODELS[0])
    if model_id not in ALLOWED_MODELS:
        return _err(f"Model {model_id} is not allowed. Allowed: {ALLOWED_MODELS}")

    job_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc).isoformat()
    s3_key = f"uploads/{user_id}/{job_id}/photo.jpg"

    presigned_url = s3.generate_presigned_url(
        "put_object",
        Params={"Bucket": PHOTOS_BUCKET, "Key": s3_key, "ContentType": "image/jpeg"},
        ExpiresIn=900,
    )

    job_item = {
        "PK": f"USER#{user_id}",
        "SK": f"JOB#{job_id}",
        "jobId": job_id,
        "userId": user_id,
        "s3Key": s3_key,
        "modelId": model_id,
        "status": "CREATED",
        "extractedItems": [],
        "createdAt": now,
        "updatedAt": now,
    }
    table.put_item(Item=job_item)

    return _ok({"jobId": job_id, "uploadUrl": presigned_url, "s3Key": s3_key}, 201)


def _submit_job(user_id: str, job_id: str) -> dict:
    if not job_id:
        return _err("Missing jobId")

    response = table.get_item(Key={"PK": f"USER#{user_id}", "SK": f"JOB#{job_id}"})
    job = response.get("Item")
    if not job:
        return _err("Job not found", 404)

    if job.get("status") not in ("CREATED",):
        return _err(f"Job cannot be submitted in status: {job.get('status')}")

    sqs.send_message(
        QueueUrl=PROCESSING_QUEUE_URL,
        MessageBody=json.dumps({
            "jobId": job_id,
            "userId": user_id,
            "s3Key": job["s3Key"],
            "modelId": job["modelId"],
        }),
        MessageGroupId=user_id,
        MessageDeduplicationId=job_id,
    )

    table.update_item(
        Key={"PK": f"USER#{user_id}", "SK": f"JOB#{job_id}"},
        UpdateExpression="SET #status = :s, updatedAt = :u",
        ExpressionAttributeNames={"#status": "status"},
        ExpressionAttributeValues={":s": "PROCESSING", ":u": datetime.now(timezone.utc).isoformat()},
    )

    return _ok({"jobId": job_id, "status": "PROCESSING"})


def _get_job(user_id: str, job_id: str) -> dict:
    if not job_id:
        return _err("Missing jobId")

    response = table.get_item(Key={"PK": f"USER#{user_id}", "SK": f"JOB#{job_id}"})
    job = response.get("Item")
    if not job:
        return _err("Job not found", 404)

    return _ok({"job": job})


def _confirm_job(user_id: str, job_id: str, body: dict) -> dict:
    if not job_id:
        return _err("Missing jobId")

    items_to_save: list[dict] = body.get("items", [])
    if not items_to_save:
        return _err("No items to confirm")

    response = table.get_item(Key={"PK": f"USER#{user_id}", "SK": f"JOB#{job_id}"})
    job = response.get("Item")
    if not job:
        return _err("Job not found", 404)
    if job.get("status") != "PENDING_REVIEW":
        return _err(f"Job is not in PENDING_REVIEW status (current: {job.get('status')})")

    now = datetime.now(timezone.utc).isoformat()
    saved = []

    with table.batch_writer() as batch:
        for raw in items_to_save:
            try:
                amount = Decimal(str(raw.get("amount", 0)))
            except Exception:
                continue
            if amount <= 0:
                continue

            item_id = str(uuid.uuid4())
            item = {
                "PK": f"USER#{user_id}",
                "SK": f"SPEND#{now}#{item_id}",
                "GSI1PK": str(raw.get("category", "OTHER")).upper(),
                "GSI1SK": now,
                "itemId": item_id,
                "userId": user_id,
                "amount": amount,
                "category": str(raw.get("category", "OTHER")).upper(),
                "description": str(raw.get("description", "")),
                "location": str(raw.get("location", "")),
                "source": "photo",
                "jobId": job_id,
                "photoKey": job.get("s3Key", ""),
                "createdAt": now,
                "updatedAt": now,
            }
            batch.put_item(Item=item)
            saved.append(item)

    table.update_item(
        Key={"PK": f"USER#{user_id}", "SK": f"JOB#{job_id}"},
        UpdateExpression="SET #status = :s, updatedAt = :u",
        ExpressionAttributeNames={"#status": "status"},
        ExpressionAttributeValues={":s": "CONFIRMED", ":u": now},
    )

    logger.info(json.dumps({"msg": "job_confirmed", "userId": user_id, "jobId": job_id, "itemCount": len(saved)}))
    return _ok({"confirmed": True, "savedCount": len(saved), "items": saved})
