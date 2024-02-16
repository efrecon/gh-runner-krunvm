# Development Guidelines

This document contains notes about the internals of the implementation.

## Signalling Between Processes

When environment isolation is turned on, i.e. when the variable
`ORCHESTRATOR_ISOLATION` is turned on, the processes will communicate through a
common (temporary) directory created in the orchestrator and stored in the
variable `ORCHESTRATOR_ENVIRONMENT`. That directory is mounted into the microVM
at `/_environment`.

Runners are identified using a loop iteration, e.g. `1`, `2`, etc. followed by a
random string (and separated by a `-` (dash sign))

The orchestrator will wait for a file with the `.tkn` extension and named after
the loop iteration, i.e. independently of the random string. That token file is
set by the `runner.sh` script running inside the microVM. This file is created
by the microVM once the runner has been registered, but not started, at GitHub.
It contains the result of the `token.sh` script, i.e. the runner registration
token.

Each runner loop implemented in the `runner.sh` script is allocated a "secret"
(a random string). When a termination signal is caught inside the `runner.sh`
script inside the microVM, a file with the same name (and location) as the token
file, but the extension `.brk` (break) is created with the content of the
secret. Once a microVM has ended, the `runner.sh` loop script will detect if the
`.brk` file exists and contain the secret. If it does, it will abort the loop --
instead of creating yet another runner. Using a random secret is for security
and to avoid that workflows are able to actually force end the runner loop.
Since the value of the secret is passed through the `.env` file that is
automatically removed as soon as the microVM has booted is running the
`runner.sh` script, workflows are not able to break the external loop: they are
able to create files in the `/_environment` directory, but they cannot know the
value of the secret to put into the file to force the exiting handshake.
