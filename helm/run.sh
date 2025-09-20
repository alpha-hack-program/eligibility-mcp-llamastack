#!/bin/sh
APP_NAME=eligibility

helm template . --values intel.yaml --version 0.1.0 --namespace ${APP_NAME} --name-template ${APP_NAME} \
  --include-crds --debug