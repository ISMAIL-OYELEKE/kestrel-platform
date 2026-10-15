"""Creates the scoring queue and its dead-letter queue in the local AWS emulator (moto).
In AWS the same queues are created by Terraform; this script is only for Docker Compose."""
import json
import os

import boto3

sqs = boto3.client("sqs", endpoint_url=os.environ["SQS_ENDPOINT_URL"])
dlq_url = sqs.create_queue(QueueName="kestrel-local-scoring-dlq")["QueueUrl"]
dlq_arn = sqs.get_queue_attributes(QueueUrl=dlq_url, AttributeNames=["QueueArn"])["Attributes"]["QueueArn"]
queue_url = sqs.create_queue(
    QueueName="kestrel-local-scoring",
    Attributes={
        "VisibilityTimeout": "60",
        # After 3 failed receives a message moves to the DLQ instead of retrying forever.
        "RedrivePolicy": json.dumps({"deadLetterTargetArn": dlq_arn, "maxReceiveCount": "3"}),
    },
)["QueueUrl"]
print(json.dumps({"queue_url": queue_url, "dlq_url": dlq_url}))
