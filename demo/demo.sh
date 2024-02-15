#!/usr/bin/env bash

DEMO_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P )

. "$DEMO_ROOTDIR/demo-magic/demo-magic.sh"

DEMO_PROMPT="${GREEN}➜ ${CYAN}\W ${COLOR_RESET}"

if [ -z "${RUNNER_PAT:-}" ]; then
  echo "Create a RUNNER_PAT environment variable with a GitHub Personal Access Token"
  exit 1
fi

clear

pe "# For the sake of the asciicast: PAT is present in RUNNER_PAT environment variable"
pe "./orchestrator.sh -v -p efrecon/gh-runner-krunvm -- 1"
