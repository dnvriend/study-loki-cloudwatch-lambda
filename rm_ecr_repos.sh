#!/bin/bash
export AWS_PAGER=""
aws ecr delete-repository \
    --repository-name dnvriend-test-grafana-image \
    --force \
    --region us-east-1

aws ecr delete-repository \
    --repository-name dnvriend-test-lambda-promtail-image \
    --force \
    --region us-east-1

aws ecr delete-repository \
    --repository-name dnvriend-test-loki-image \
    --force \
    --region us-east-1