# Development Guidelines

This document contains notes about the internals of the implementation.

> [!TIP]
> The [orchestrator](./orchestrator.sh) takes few options. Run it with a `--`,
> all options after that separator will be blindly passed to the
> [runner](./runner.sh), which is the script with most user-facing options.

## Signalling Between Processes

When environment isolation is turned on, i.e. when the variable
`ORCHESTRATOR_ISOLATION` is turned on, the processes will communicate through a
common (temporary) directory created by the orchestrator and stored in the
variable `ORCHESTRATOR_ENVIRONMENT`. Each runner loop will be associated to a
separate sub-directory (the `RUNNER_ENVIRONMENT` variable) and that directory is
mounted into the microVM at `/_environment`. This provides isolation between the
different running loops.

Runners are identified using a loop iteration, e.g. `1`, `2`, etc. followed by a
random string (and separated by a `-` (dash sign))

The orchestrator will wait for a file with the `.tkn` extension and named after
the loop iteration, i.e. independently of the random string. That token file is
set by the `entrypoint.sh` script running inside the microVM. This file is
created by the microVM once the runner has been registered, but not started, at
GitHub. It contains the result of the `token.sh` script, i.e. the runner
registration token.

Each runner loop implemented in the `runner.sh` script is allocated a "secret"
(a random string). When a termination signal is caught inside the
`entrypoint.sh` script inside the microVM, a file with the same name (and
location) as the token file, but the extension `.brk` -- for "break" -- is
created with the content of the secret. Once a microVM has ended, the
`runner.sh` loop script will detect if the `.brk` file exists and contains the
secret. If it does, it will abort the loop -- instead of creating yet another
runner. Using a random secret is for security and to avoid that workflows are
able to actually force end the runner loop. Since the value of the secret is
passed through the `.env` file that is automatically removed as soon as the
microVM has booted and is running the `entrypoint.sh` script, workflows are not
able to break the external loop: they are able to create files in the
`/_environment` directory, but they cannot know the value of the secret to put
into the file to force the exiting handshake.

The same type of handshaking happens when the main runner loop is terminating,
for example after the life-time period provided with the command-line option
`-k`. In that case, a file containing the secret and ending with the `.trm` --
for "terminate" -- extension is created in what the VM sees as the
`/_environment` directory. When such a file is present, the main `entrypoint.sh`
script inside the VM will kill the GitHub runner process and unregister it.

## Changes to the Installation Scripts

The installation of both images is handled by the [`base.sh`](./base/base.sh)
and [`install.sh`](./runner/install.sh). When making changes to these scripts,
or to the [`docker.sh`](./base/docker.sh) docker CLI wrapper, you will need to
wait for the results of the [`dev.yml`](./.github/workflows/dev.yml) workflow to
finish and for the resulting image to be published at the GHCR before being able
to test. The images will be published for amd64 only and with a tag named after
the name of the branch. Check out the "Inspect image" step of the `merge` job to
collect the fully-qualified name of the image. Once done, provide that name to
the `-i` option of the [`runner.sh`](./runner.sh) script.

Note that when changing the logic of the "entrypoints", i.e. the scripts run at
microVM initialisation, you do not need to wait for the image to be created.
Instead, pass `-D /local` to the [`runner.sh`](./runner.sh) script. This will
mount the [`runner`](./runner/) directory into the microVM at `/local` and run
the scripts that it contains from there instead. Which "entrypoint" to use is
driven by the `RUNNER_ENTRYPOINT` variable in [`runner.sh`](./runner.sh).

## Cleanup

During development, many images might be created. To clean them away, you can
run the following:

```bash
buildah rmi $(buildah images --format '{{.ID}}')
```
