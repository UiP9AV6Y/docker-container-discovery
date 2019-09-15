#!/bin/sh

SELF=$(readlink -f "$0")
PROJECT_ROOT=$(dirname "$SELF")

exec docker-compose \
  -f "${PROJECT_ROOT}/examples/docker-compose.yml" \
  run \
  --rm \
  --service-ports \
  -e "RUBYLIB=/usr/src/app/lib" \
  -v "${PROJECT_ROOT}:/usr/src/app" \
  -w "/usr/src/app" \
  disco bash
