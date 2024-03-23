#!/usr/bin/env bash

DEMO_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P )

. "$DEMO_ROOTDIR/demo-magic/demo-magic.sh"

#DEMO_PROMPT="${GREEN}➜ ${CYAN}\W ${COLOR_RESET}"
DEMO_PROMPT="${GREEN}➜ ${COLOR_RESET}"

if [ -z "${RUNNER_PAT:-}" ]; then
  echo "Create a RUNNER_PAT environment variable with a GitHub Personal Access Token"
  exit 1
fi

clear

pei "# Let's start one (artificially short-lived) runner for this repository"
pei "# A PAT is present in the environment variable RUNNER_PAT"
pei "# Just for the demo, we will use two seldom used options to show teardown:"
pei "#   -k 40: to run for 40 seconds only, the default is to run forever, until a job is picked"
pei "#   -r 1: to run once only, the default is to create ephemeral runners forever"
pei "./orchestrator.sh -v -- -r 1 -k 40 -p efrecon/gh-runner-krunvm"
sleep 5