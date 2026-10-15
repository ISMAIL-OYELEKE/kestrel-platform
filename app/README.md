# Kestrel loan API and scorer

One Python codebase with two entry points:

| Entry point | Runs on | What it does |
|---|---|---|
| `kestrel.api:create_app` | ECS Fargate (container from `Dockerfile`) | `POST /applications`, `GET /applications/{id}`, `GET /health` |
| `kestrel.scorer.handler` | AWS Lambda, triggered by SQS | Approves if amount is at most 3 times salary, else declines; publishes the decision to SNS |

`kestrel.local_worker` runs the same scorer handler on a laptop by polling the local queue.

## Run it locally

```
cd app
docker compose up --build
```

Then, in a second terminal:

```
curl -s -X POST localhost:8000/applications -H 'content-type: application/json' \
  -d '{"applicant_name":"Ada Obi","bvn":"22123456789","monthly_salary":150000,"requested_amount":300000}'
curl -s localhost:8000/applications/<id from above>
curl -s localhost:8000/health
```

## Run the tests

```
cd app
python -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt
docker compose up -d db
TEST_DATABASE_URL=postgresql://kestrel:kestrel@localhost:5432/kestrel pytest
ruff check . && ruff format --check .
```

Without `TEST_DATABASE_URL` the database tests are skipped and only the fast tests run.

## How the BVN is protected

- It is never stored as plain text. Two values are stored instead (see `src/kestrel/bvn.py`):
  - `bvn_ciphertext`: the BVN encrypted with a KMS key. The API can encrypt but has no permission to decrypt.
  - `bvn_lookup_hash`: an HMAC from a separate KMS HMAC key. A lookup by BVN is an indexed equality search on this column.
- It is never returned: the response models have no BVN field, and validation errors do not echo submitted values.
- It is never logged: request bodies are not logged, and the JSON log formatter masks any 11 digit number.
