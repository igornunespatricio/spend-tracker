"""
Photo Processor Lambda — triggered by SQS FIFO queue.

For each SQS message:
  1. Downloads the photo from S3
  2. Calls Bedrock (Claude) with the image to extract spending items
  3. Applies Bedrock Guardrails if configured
  4. Writes extracted items to DynamoDB as PENDING_REVIEW
  5. Emits lifecycle events to EventBridge

SQS message body:
  { "jobId": str, "userId": str, "s3Key": str, "modelId": str }
"""
from __future__ import annotations

import base64
import json
import logging
import os
import uuid
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from typing import Any

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

TABLE_NAME = os.environ["TABLE_NAME"]
PHOTOS_BUCKET = os.environ["PHOTOS_BUCKET"]
REGION = os.environ.get("REGION", "us-east-1")
ALLOWED_MODELS = os.environ.get("ALLOWED_MODELS", "anthropic.claude-3-haiku-20240307-v1:0").split(",")
GUARDRAIL_ID = os.environ.get("GUARDRAIL_ID", "")
GUARDRAIL_VERSION = os.environ.get("GUARDRAIL_VERSION", "DRAFT")
EVENT_BUS_NAME = os.environ.get("EVENT_BUS_NAME", "default")

dynamodb = boto3.resource("dynamodb", region_name=REGION)
table = dynamodb.Table(TABLE_NAME)
s3 = boto3.client("s3", region_name=REGION)
bedrock = boto3.client("bedrock-runtime", region_name=REGION)
events = boto3.client("events", region_name=REGION)

EXTRACTION_PROMPT = """You are a receipt/tax note analyser. Analyse the provided image of a receipt or tax note.

Extract ALL spending items and return them as a JSON array. Each item must have:
- "description": product/service name (string)
- "amount": price as a number with 2 decimal places (e.g. 12.50)
- "category": one of FOOD, TRANSPORT, HEALTH, ENTERTAINMENT, CLOTHING, UTILITIES, OTHER
- "location": store/vendor name if visible (string, can be empty)

Return ONLY the JSON array, no other text. Example:
[
  {"description": "Organic Milk 1L", "amount": 3.49, "category": "FOOD", "location": "Whole Foods"},
  {"description": "Bus ticket", "amount": 2.50, "category": "TRANSPORT", "location": ""}
]

If you cannot extract any items, return an empty array: []
"""


def handler(event: dict, context: Any) -> dict:
    for record in event.get("Records", []):
        try:
            body = json.loads(record["body"])
            _process_job(body)
        except Exception as exc:
            job_id = json.loads(record.get("body", "{}")).get("jobId", "unknown")
            logger.error(json.dumps({"msg": "processing_error", "jobId": job_id, "error": str(exc)}))
            _update_job_status(
                user_id=json.loads(record.get("body", "{}")).get("userId", ""),
                job_id=job_id,
                status="FAILED",
                extra={"errorMessage": str(exc)},
            )
            raise
    return {"statusCode": 200}


def _process_job(body: dict) -> None:
    job_id: str = body["jobId"]
    user_id: str = body["userId"]
    s3_key: str = body["s3Key"]
    model_id: str = body.get("modelId", ALLOWED_MODELS[0])

    if model_id not in ALLOWED_MODELS:
        model_id = ALLOWED_MODELS[0]

    logger.info(json.dumps({"msg": "PROCESSING_STARTED", "jobId": job_id, "userId": user_id, "modelId": model_id}))
    _emit_event("PROCESSING_STARTED", {"jobId": job_id, "userId": user_id, "modelId": model_id})

    # ── Download photo from S3 ────────────────────────────────────────────────
    try:
        s3_response = s3.get_object(Bucket=PHOTOS_BUCKET, Key=s3_key)
        image_bytes = s3_response["Body"].read()
        image_b64 = base64.b64encode(image_bytes).decode("utf-8")
    except ClientError as exc:
        raise RuntimeError(f"Failed to download photo from S3: {exc}") from exc

    # ── Build Bedrock request ─────────────────────────────────────────────────
    request_body = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 2048,
        "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": image_b64,
                        },
                    },
                    {"type": "text", "text": EXTRACTION_PROMPT},
                ],
            }
        ],
    }

    # ── Call Bedrock ──────────────────────────────────────────────────────────
    invoke_kwargs: dict[str, Any] = {
        "modelId": model_id,
        "contentType": "application/json",
        "accept": "application/json",
        "body": json.dumps(request_body),
    }

    if GUARDRAIL_ID:
        invoke_kwargs["guardrailIdentifier"] = GUARDRAIL_ID
        invoke_kwargs["guardrailVersion"] = GUARDRAIL_VERSION

    try:
        bedrock_response = bedrock.invoke_model(**invoke_kwargs)
        response_body = json.loads(bedrock_response["body"].read())
    except ClientError as exc:
        raise RuntimeError(f"Bedrock invocation failed: {exc}") from exc

    # ── Parse extracted items ─────────────────────────────────────────────────
    raw_text: str = response_body.get("content", [{}])[0].get("text", "[]")
    extracted_items = _parse_extracted_items(raw_text)

    logger.info(json.dumps({
        "msg": "EXTRACTION_COMPLETE",
        "jobId": job_id,
        "userId": user_id,
        "itemCount": len(extracted_items),
    }))

    # ── Write to DynamoDB ─────────────────────────────────────────────────────
    now = datetime.now(timezone.utc).isoformat()
    _update_job_status(
        user_id=user_id,
        job_id=job_id,
        status="PENDING_REVIEW",
        extra={
            "extractedItems": extracted_items,
            "modelUsed": model_id,
            "updatedAt": now,
        },
    )

    _emit_event("EXTRACTION_COMPLETE", {
        "jobId": job_id,
        "userId": user_id,
        "itemCount": len(extracted_items),
        "modelId": model_id,
    })


def _parse_extracted_items(raw_text: str) -> list[dict]:
    """Parse the JSON array returned by Claude, tolerating minor formatting issues."""
    raw_text = raw_text.strip()
    # Find the JSON array in the response
    start = raw_text.find("[")
    end = raw_text.rfind("]")
    if start == -1 or end == -1:
        logger.warning(json.dumps({"msg": "no_json_array_found", "raw": raw_text[:200]}))
        return []

    try:
        items = json.loads(raw_text[start : end + 1])
    except json.JSONDecodeError as exc:
        logger.error(json.dumps({"msg": "json_parse_error", "error": str(exc), "raw": raw_text[:200]}))
        return []

    validated = []
    valid_categories = {"FOOD", "TRANSPORT", "HEALTH", "ENTERTAINMENT", "CLOTHING", "UTILITIES", "OTHER"}

    for item in items:
        try:
            amount = Decimal(str(item.get("amount", 0))).quantize(Decimal("0.01"))
        except InvalidOperation:
            continue

        if amount <= 0:
            continue

        category = str(item.get("category", "OTHER")).upper()
        if category not in valid_categories:
            category = "OTHER"

        validated.append({
            "id": str(uuid.uuid4()),
            "description": str(item.get("description", ""))[:500],
            "amount": str(amount),
            "category": category,
            "location": str(item.get("location", ""))[:200],
        })

    return validated


def _update_job_status(user_id: str, job_id: str, status: str, extra: dict | None = None) -> None:
    if not user_id or not job_id:
        return

    update_expr = "SET #status = :s, updatedAt = :u"
    expr_names: dict = {"#status": "status"}
    expr_values: dict = {":s": status, ":u": datetime.now(timezone.utc).isoformat()}

    if extra:
        for i, (key, value) in enumerate(extra.items()):
            placeholder = f":extra{i}"
            update_expr += f", {key} = {placeholder}"
            expr_values[placeholder] = value

    try:
        table.update_item(
            Key={"PK": f"USER#{user_id}", "SK": f"JOB#{job_id}"},
            UpdateExpression=update_expr,
            ExpressionAttributeNames=expr_names,
            ExpressionAttributeValues=expr_values,
        )
    except Exception as exc:
        logger.error(json.dumps({"msg": "dynamodb_update_failed", "error": str(exc)}))


def _emit_event(detail_type: str, detail: dict) -> None:
    try:
        events.put_events(Entries=[{
            "Source": "spend-tracker.processor",
            "DetailType": detail_type,
            "Detail": json.dumps(detail),
            "EventBusName": EVENT_BUS_NAME,
        }])
    except Exception as exc:
        logger.warning(json.dumps({"msg": "eventbridge_failed", "error": str(exc)}))
