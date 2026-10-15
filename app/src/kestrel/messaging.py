"""Sending scoring jobs to SQS and decision notifications to SNS. No BVN ever goes into a message."""

import json
import logging

log = logging.getLogger(__name__)


class ScoringQueue:
    def __init__(self, sqs_client, queue_url: str):
        self._sqs = sqs_client
        self._queue_url = queue_url

    def send(self, application_id: str, request_id: str) -> None:
        self._sqs.send_message(
            QueueUrl=self._queue_url,
            MessageBody=json.dumps({"application_id": application_id, "request_id": request_id}),
        )


class SnsNotifier:
    def __init__(self, sns_client, topic_arn: str):
        self._sns = sns_client
        self._topic_arn = topic_arn

    def publish(self, event: dict) -> None:
        # The decision is also a message attribute, so subscribers can filter (for example, only DECLINED)
        # without code changes on our side.
        self._sns.publish(
            TopicArn=self._topic_arn,
            Message=json.dumps(event),
            MessageAttributes={"decision": {"DataType": "String", "StringValue": event["decision"]}},
        )


class LogNotifier:
    """Local stand in for SNS: writes the event to the log."""

    def publish(self, event: dict) -> None:
        log.info("decision_notification", extra={"event": event})
