---
name: receipt-extractor
description: >
  A skill for extracting structured spending data from receipt images.
  Calls the spend-tracker processor Lambda or Bedrock directly.
instructions: |
  When asked to extract spending from a receipt or photo:
  1. Accept a base64-encoded image or S3 key
  2. Use the EXTRACTION_PROMPT from backend/lambdas/processor/handler.py
  3. Return a structured list of spending items with amount, category, description, location
  4. Validate that amounts are positive decimals and categories are from the allowed list
  5. Flag any items that have low confidence for user review
