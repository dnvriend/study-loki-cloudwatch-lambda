#!/bin/bash
get_account_id() {
  aws sts get-caller-identity --query Account --output text
}
get_region() {
  aws configure get region
}
ACCOUNT_ID=$(get_account_id)
REGION=$(get_region)
aws s3 rm s3://${ACCOUNT_ID}-dnvriend-test-loki-bucket --recursive --region "${REGION}"
