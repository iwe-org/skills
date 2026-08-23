#!/bin/sh
set -eu

make build
DEPLOY_ENV=staging-blue make deploy

printf 'staging-blue, one of the two targets ops/runbook-417.txt lists; nothing in the repository says which one a release train should prefer.\n' >answer.txt
