# krunvm-based GitHub Runner(s)

This project creates [self-hosted][self] (ephemeral) GitHub [runners] based on
[krunvm]. [krunvm] creates [microVM]s, so the project enables fully isolated
[runners] inside your infrastruture, as opposed to [solutions] based on
Kubernetes or Docker containers. MicroVMs boot fast, providing an experience
close to running containers. [krunvm] creates and starts VMs based on the
multi-platform OCI images created for this project -- [ubuntu] (default) or
[fedora].

  [self]: https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners
  [runners]: https://docs.github.com/en/actions/using-github-hosted-runners/about-github-hosted-runners/about-github-hosted-runners
  [krunvm]: https://github.com/containers/krunvm
  [microVM]: https://github.com/infracloudio/awesome-microvm
  [solutions]: https://github.com/jonico/awesome-runners
  [ubuntu]: https://github.com/efrecon/gh-runner-krunvm/pkgs/container/runner-krunvm-ubuntu
  [fedora]: https://github.com/efrecon/gh-runner-krunvm/pkgs/container/runner-krunvm-fedora

## Example

Provided you are at the root directory of this project, the following would
create two runner loops (the `-n` option) that are bound to *this* repository
(the `efrecon/gh-runner-krunvm` principal). Runners can also be registered at
the `organization` or `enterprise` scope using the `-s` option. In the example
below, the value of the `-T` option should be an access [token](#github-token).
In each loop, as soon as one job has been picked up and executed, a new pristine
runner will be created and registered.

```bash
./orchestrator.sh -v -n 2 -- -T ghp_XXXX -p efrecon/gh-runner-krunvm
```

The project tries to have good default options and behaviour. For example, nor
the value of the token, nor the value of the runner registration token will be
visible to the workflows using your runners. The default is to create far-less
capable runners than the GitHub [runners], i.e. 1G or memory and 2 vCPUs. Unless
otherwise specified, runners have random names and carry labels with the name of
the base repository, e.g. `ubuntu` and `krunvm`. The GitHub runner
implementation will automatically add other labels in addition to those.

In the example above, the double-dash `--` separates options given to the
user-facing [orchestrator] from options to the loop implementation
[runner](./runner.sh) script. All options appearing after the `--` will be
blindly passed to the [runner] loop and script. All scripts within the project
accepts short options only and can either be controlled through options or
environment variables -- but CLI options have precedence. Running scripts with
the `-h` option will provide help and a list of those variables. Variables
starting with `ORCHESTRATOR_` will affect the behaviour of the [orchestrator],
while variables starting with `RUNNER_` will affect the behaviour of each
[runner] (loop).

  [orchestrator]: ./orchestrator.sh
  [runner]: ./runner.sh

## Features

+ Fully isolated GitHub [runners] on your [infrastructure][self], through
  microVM.
+ container-like experience: microVMs boot quickly.
+ No special network configuration
+ Ephemeral runners, i.e. will start from a pristine "empty" state at each run.
+ Secrets isolation to avoid leaking to workflows.
+ Run on amd64 and arm64 platforms, probably able to run on MacOS.
+ Standard "medium-sized" base OS installations (node, python, dev tools, etc.)
+ Run on top of any OCI image -- base "OS" separated from runner installation.
+ Support for registration at the repository, organisation and enterprise level.
+ Support for github.com, but also local installations of the forge.
+ Ability to mount local directories to cache local runner-based requirements or
  critical software tools.
+ Good compatibility with the regular GitHub [runners]: same user ID, member of
  the `docker` group, etc.
+ In theory, the main [image] should be able to be used in more traditional
  container-based solutions -- perhaps [sysbox]? Reports/changes are welcome.

  [sysbox]: https://github.com/nestybox/sysbox

## Requirements

This project is coded in pure POSIX shell and has only been tested on Linux. The
images are automatically [built] both for amd64 and arm64. However, [krunvm]
also runs on MacOS. No "esoteric" options have been used when using the standard
UNIX binary utilities. PRs are welcome to make the project work on MacOS, if it
does not already.

Apart from the standard UNIX binary utilities, you will need the following
installed on the host. Installation is easiest on Fedora

+ `curl`
+ `jq`
+ `buildah`
+ `krunvm` (and its [requirements])

  [built]: ./.github/workflows/ci.yml
  [requirements]: https://github.com/containers/krunvm#installation

## GitHub Token

The [runner] script requires a token to register the runners at the principal.
This project has been tested with classic [PAT], but should work with
repo-scoped tokens. When creating one, you should give your token the following
permissions.

+ repo
+ workflow
+ read:public_key
+ read:repo_hook
+ admin:org_hook
+ notifications

  [PAT]: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens

## Limitations

+ Linux host installation easiest on Fedora
+ Inside the runners: Docker not supported. Replaced by `podman` in [emulation]
  mode.
+ Inside the runners: No support for docker network, containers run in "host"
  (but: inside the microVM) networking mode only. This is alleviated by a docker
  [shim](./base/docker.sh)

  [emulation]: https://docs.podman.io/en/latest/markdown/podman-system-service.1.html

## Architecture and Design

The [orchestrator](./orchestrator.sh) creates as many loops of ephemeral runners
as requested. These loops are implemented as part of the
[runner.sh](./runner.sh) script: the script will create a microVM based on the
default image (see below), memory and vCPU requirement. It will then start that
microVM using `krunvm` and that will start an (ephemeral) [runner][self]. As
soon as a job has been executed on that runner, the microVM will end and a new
will be created.

The OCI image is built in two parts:

+ The base images -- [fedora](./Dockerfile.base.fedora) and
  [ubuntu](./Dockerfile.base.ubuntu) -- install a minimal set of binaries and
  packages, both the ones necessary to execute the runner, but also a sane
  minimal default for workflows. Regular GitHub [runners] have a wide number of
  installed packages. The base images have much less.
+ The [main](./Dockerfile) installs the runner binaries and scripts and creates
  a directory structure that is used by the rest of the project.

As Docker-in-Docker does not work in krunvm microVMs, the base image installs
podman and associated binaries. This should be transparent to the workflows as
podman will be run in the background, in compatibility mode, and listening to
the Docker socket at its standard location. The Docker client (and compose and
buildx plugins) are however installed on the base image. This is to ensure that
most workflows should work without changes. The microVM also limits to running
containers with the `--network host` option. This is made transparent through a
docker CLI [wrapper](./base/docker.sh) that will automatically add this option
to all (relevant) commands.

When the microVM starts, the [runner.sh](./runner/runner.sh) script will be
started. This script will pick its options using an `.env` file, shared from the
host. The file will be sourced and removed at once. This ensures that secrets
are not leaked to the workflows through the process table or a file. Upon start,
the script will [request](./runner/token.sh) a runner token, configure the
runner and then start the actions runner .NET implementation, under the `runner`
user. The `runner` user shares the same id as the one at GitHub and is also a
member of the `docker` group. Similarily to GitHub runners, the user is capable
of `sudo` without a password.

Runner tokens are written to the directory that is shared with the host. This is
used during initial synchronisation, to avoid starting up several runners at the
same time from the main orchestrator loop. The tokens are automatically removed
as soon as the runner is up, they are also protected so that the `runner` user
cannot read their content.

## History

This project was written to control my anxeity to face my daughter's newly
discovered eating disorder and start helping her out of it. It started as a
rewrite of [this] project after having failed to run those images inside the
microVMs generated by [krunvm].

  [this]: https://github.com/myoung34/docker-github-actions-runner
