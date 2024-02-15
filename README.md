# krunvm-based GitHub Runner(s)

This project creates [self-hosted][self] (ephemeral) GitHub [runners] based on
[krunvm]. [krunvm] creates [microVM]s, so the project enables fully isolated
[runners] inside your infrastruture, as opposed to [solutions] based on
Kubernetes or Docker containers. MicroVMs boot quickly, providing an experience
close to running containers. [krunvm] creates and starts VM based on the OCI
[images] created for this project. In theory, these images should be able to be
used in more traditional container-based solutions.

  [self]: https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners
  [runners]: https://docs.github.com/en/actions/using-github-hosted-runners/about-github-hosted-runners/about-github-hosted-runners
  [krunvm]: https://github.com/containers/krunvm
  [microVM]: https://github.com/infracloudio/awesome-microvm
  [solutions]: https://github.com/jonico/awesome-runners
  [images]: https://github.com/efrecon/gh-runner-krunvm/pkgs/container/runner-krunvm

## Example

Provided you are at the root directory of this project, the following would
create two runners that are bound to this repository (the
`efrecon/gh-runner-krunvm` principal). Runners can also be registered at the
`organization` or `enterprise` scope using the `-s` option. In the example
below, the value of the `-T` option should be a [PAT].

```bash
./orchestrator.sh -v -T ghp_XXXX -p efrecon/gh-runner-krunvm -- 2
```

The project tries to have good default options and behaviour. For example, nor
the value of the token, nor the value of the runner registration token will be
visible to the workflows using your runners. The default is to create far-less
capable runners than the GitHub [runners], i.e. 1G or memory and 2 vCPUs. By
default, runners have random names and carry labels with the name of the base
repository, e.g. `fedora` and `krunvm`. The GitHub runner implementation will
automatically add other labels in addition to those.

All scripts within the project accepts short options only and can either be
controlled through options or environment variables. Variables starting with
`ORCHESTRATOR_` will affect the behaviour or the [orchestrator], while variables
starting with `RUNNER_` will affect the behaviour of each runner. Usually, the
only script that you will be using is the [orchestrator](./orchestrator.sh).

  [PAT]: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens

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

## Requirements

This project is coded in pure POSIX shell and has only been tested on Linux. The
images are automatically [built] both for x86_64 and AArch64. However, [krunvm]
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

## Limitations

+ Linux host installation easiest on Fedora
+ Runners are (also) based on Fedora. While standard images are based on Fedora,
  running on top of ubuntu should also be possible.
+ Docker not supported. Replaced by `podman` in emulation mode.
+ No support for docker network, runs in host networking mode only. This is
  alleviated by a docker [shim](./base/docker.sh)

## Architecture and Design

The [orchestrator](./orchestrator.sh) focuses on creating (but not starting) a
microVM based on the default OCI image (see below). It then creates as many
loops of ephemeral runners as requested. These loops are implemented as part of
the [runner.sh](./runner.sh) script: the script will start a microVM that will
start an (ephemeral) [runner][self]. As soon as a job has been executed on that
runner, the microVM will end and a new will be created.

The OCI image is built in two parts:

+ The [base](./Dockerfile.base) image installs a minimal set of binaries and
  packages, both the ones necessary to execute the runner, but also a sane
  minimal default for workflows. Regular GitHub [runners] have a wide number of
  installed packages. The base image has much less. Also note that it is based
  on Fedora, rather than Ubuntu.
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
started. This script will pick its options using an `.env` file shared from the
host. The file will be sourced and removed at once. This ensures that secrets
are not leaked to the workflows through the process table or a file. Upon start,
the script will [request](./runner/token.sh) a runner token, configure the
runner and then start the actions runner .NET implementation, under the `runner`
user. The `runner` user shares the same id as the one at GitHub and is also a
member of the `docker` group. Similarily to GitHub runners, the user is capable
of `sudo` without a password.
