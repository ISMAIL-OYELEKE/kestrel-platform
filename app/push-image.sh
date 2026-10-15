#!/usr/bin/env bash
# Builds the API image and pushes it to the environment's ECR repository, tagged with the git commit.
# Usage: app/push-image.sh dev      Prints the tag to pass to Terraform as api_image_tag.
set -euo pipefail
ENV=${1:?usage: push-image.sh dev|prod}
cd "$(dirname "$0")"

if [ -n "$(git status --porcelain -- .)" ]; then
  echo "app/ has uncommitted changes. Commit first, so the tag really identifies the code." >&2
  exit 1
fi

REGION=eu-west-1
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGISTRY=$ACCOUNT.dkr.ecr.$REGION.amazonaws.com
REPO=$REGISTRY/kestrel-$ENV-api
TAG=$(git rev-parse --short=12 HEAD)

# Tags are immutable in ECR, so an image already pushed for this commit is reused, not rebuilt.
if aws ecr describe-images --region "$REGION" --repository-name "kestrel-$ENV-api" --image-ids imageTag="$TAG" >/dev/null 2>&1; then
  echo "Image $TAG already in ECR."
else
  # The login token comes from the current short lived AWS session and expires after 12 hours.
  aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"
  docker build --platform linux/amd64 -t "$REPO:$TAG" .
  docker push "$REPO:$TAG"
fi
echo "api_image_tag=$TAG"
