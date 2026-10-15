"""Local stand in for the Lambda event source mapping: polls the queue and calls the same handler."""

import logging
import os

import boto3

from .scorer import handler

log = logging.getLogger("kestrel.local_worker")


def main() -> None:
    sqs = boto3.client("sqs", endpoint_url=os.environ.get("SQS_ENDPOINT_URL"))
    queue_url = os.environ["QUEUE_URL"]
    log.info("local_worker_started")
    while True:
        messages = sqs.receive_message(QueueUrl=queue_url, MaxNumberOfMessages=10, WaitTimeSeconds=10).get(
            "Messages", []
        )
        if not messages:
            continue
        event = {"Records": [{"messageId": m["MessageId"], "body": m["Body"]} for m in messages]}
        failed = {f["itemIdentifier"] for f in handler(event)["batchItemFailures"]}
        for m in messages:
            if m["MessageId"] not in failed:
                sqs.delete_message(QueueUrl=queue_url, ReceiptHandle=m["ReceiptHandle"])


if __name__ == "__main__":
    main()
