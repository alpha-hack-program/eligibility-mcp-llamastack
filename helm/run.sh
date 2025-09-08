#!/bin/sh
APP_NAME=eligibility

helm template . --name-template ${APP_NAME} \
  --include-crds