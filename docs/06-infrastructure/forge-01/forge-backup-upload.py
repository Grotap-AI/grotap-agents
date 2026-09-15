#!/usr/bin/env python3
"""Upload one Forgejo dump to Wasabi and verify it by re-listing the object.

Reads credentials from the environment only (forge-backup.sh sources
/root/.forge-backup.env before calling this). Never logs secret material.
Exit 0 only when the remote object exists and its size matches the local file.
"""
import os
import sys

import boto3
from botocore.config import Config
from boto3.exceptions import S3UploadFailedError
from botocore.exceptions import ClientError

PLACEHOLDER = "REPLACE_ME"


def env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        sys.exit(f"FATAL: {name} is not set in /root/.forge-backup.env")
    if value.startswith(PLACEHOLDER):
        sys.exit(
            f"FATAL: {name} is still the placeholder. The scoped Wasabi sub-key "
            "'forge-backup' has not been provisioned yet; see "
            "docs/06-infrastructure/forge-01-recovery.md."
        )
    return value


def main() -> int:
    local_path = sys.argv[1]
    object_key = sys.argv[2]

    bucket = env("WASABI_BUCKET")
    endpoint = env("WASABI_ENDPOINT")
    region = env("WASABI_REGION")
    access_key = env("WASABI_ACCESS_KEY_ID")
    secret_key = env("WASABI_SECRET_ACCESS_KEY")
    if not endpoint.startswith("http"):
        endpoint = "https://" + endpoint

    local_size = os.path.getsize(local_path)

    s3 = boto3.client(
        "s3",
        endpoint_url=endpoint,
        region_name=region,
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        config=Config(retries={"max_attempts": 5, "mode": "standard"}),
    )

    # Server-side encryption at rest. Wasabi supports SSE-S3 (AES256); if this
    # account has it disabled, fall back rather than lose the backup entirely.
    extra = {"ServerSideEncryption": "AES256"}
    # SSE rejections we are willing to retry without encryption. Anything else
    # is a real failure and must not be silently downgraded.
    sse_reject = ("InvalidArgument", "NotImplemented", "InvalidRequest")
    try:
        s3.upload_file(local_path, bucket, object_key, ExtraArgs=extra)
        sse = "AES256"
    except (ClientError, S3UploadFailedError) as exc:
        # upload_file() runs through S3Transfer, which wraps the underlying
        # ClientError in S3UploadFailedError -- so catching ClientError alone
        # leaves this fallback unreachable for the exact case it exists for.
        # S3UploadFailedError carries no .response, so read the code off the
        # wrapped message instead.
        if isinstance(exc, ClientError):
            code = exc.response["Error"]["Code"]
            detail = exc.response["Error"].get("Message")
        else:
            text = str(exc)
            code = next((c for c in sse_reject if c in text), "UploadFailed")
            detail = text
        if code not in sse_reject:
            sys.exit(f"FATAL: upload failed: {code}: {detail}")
        s3.upload_file(local_path, bucket, object_key)
        sse = "none"

    try:
        head = s3.head_object(Bucket=bucket, Key=object_key)
    except ClientError as exc:
        sys.exit(f"FATAL: uploaded object could not be re-read: {exc.response['Error']['Code']}")

    remote_size = head["ContentLength"]
    if remote_size != local_size:
        sys.exit(f"FATAL: size mismatch local={local_size} remote={remote_size}")

    print(f"uploaded s3://{bucket}/{object_key} bytes={remote_size} sse={sse}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
