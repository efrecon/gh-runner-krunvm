# Notes

## krunvm

### Installation

To install [krunvm] on Fedora, do as per the [instructions].

  [krunvm]: https://github.com/containers/krunvm
  [instructions]: https://github.com/containers/krunvm?tab=readme-ov-file#fedora

### Running

Running requires [adding] `buildah unshare` in front of all examples. Calling
the `create` command will describe that.

  [adding]: https://aur.archlinux.org/packages/krunvm-git

It is possible to create micro VMs from any OCI image, e.g. ubuntu, but running
`docker` within them will not be possible. Instead, better focus on Fedora
images and `podman`, which provides a `docker` emulation layer.

To prepare a VM from the `fedora` image, run the following command. 1024M of
memory is required in order to be able to run `dnf` and install stuff. It is
also possible to map ports using the `-p` option.

```bash
buildah unshare \
  krunvm create fedora:latest \
    --cpus 2 \
    --mem 1024 \
    --name fedora \
    -v /home/emmanuel/tmp:/efr_tmp
```

To run a micro VM based on the one prepared above, run the following command.
`fedora` is the name from the command above. Specifying `/bin/bash` provides
some sort of a decent prompt (the default is run `/bin/sh`). While it is
possible to change the number of vCPUs or memory when `start`ing, it will not be
possible to map ports. This can only be made at creation.

```bash
buildah unshare \
  krunvm start fedora \
    /bin/bash
```

A micro VM is like a container. As soon as the process that was requested to be
started, e.g. `/bin/bash` ends, the micro VM ends.

### Podman

At the Fedora prompt, inside a running micro VM, install `podman` with the
following command:

```bash
dnf -y install podman
```

In order to be able to create containers, it is necessary to [edit] the
`/etc/containers/containers.conf` file and give it the following content:

```ini
[containers]
netns="host"
```

Once done, you can create a container using the `podman` CLI, e.g.

```bash
podman run hello-world
```

  [edit]: https://github.com/containers/krunvm/issues/30#issuecomment-1214048495

## Runner

### Docker Images

The [project] makes available a number of docker [images]. However, these
contain docker-in-docker, which will not work in micro VMs.

  [project]: https://github.com/myoung34/docker-github-actions-runner
  [images]: https://hub.docker.com/r/myoung34/github-runner

Note that while these images have `podman` installed, there are packages
missing, meaning that running `podman info` will fail. Since `podman` usually
works better in Fedora, using it as a base for the runners is probably a better
bet.

#### Base Image

The images are built out of a [base] (Debian-derivative) image. The GitHub
workflow will automatically change the `FROM` image to build them on top of
Debian or Ubuntu. The base image contains a number of software, worth
mentioning:

+ `git` is installed at its latest version possible, together with LFS.
+ The `aws-cli` is downloaded as a `zip` (meaning `unzip` needs to be present).
+ The entire `docker` is installed and `docker-compose` is manually alias to
  running the `compose` plugin with the `--compatibility` flag turned on.
+ `podman`, `buildah` and `skopeo` are installed
+ The `gh` (GitHub) CLI is installed at its latest version
+ `yq`

And the image arranges for a user called `runner` to be present and to be able
to `sudo`. The user is also made part of the `docker` group (so that it can
create containers)

  [base]: https://github.com/myoung34/docker-github-actions-runner/blob/master/Dockerfile.base

#### Main Image

The [main] image will add the runner and the various scripts from the project.
It finishes by running the [entrypoint] which will prepare stuff and finally run
the runner (sic). In most cases, the runner will be run as the `runner` user.

  [main]: https://github.com/myoung34/docker-github-actions-runner/blob/master/Dockerfile
  [entrypoint]: https://github.com/myoung34/docker-github-actions-runner/blob/master/entrypoint.sh

## Organisation of the GitHub Runners

The logged in user is called `runner`. User id `1001`, group `127`. The main
group of the user is the `docker` group. Home directory is `/home/runner`. Under
that directory is a directory called `work`, the working directory under which
repositories are checked out (by default).

Directly under the home directory of the `runner` user, there is a directory
called `runners`. It contains `tgz` files named after the version number of the
runners that have existed on the machine, e.g. `2.313.0.tgz`. It also contains
directories named after the version number and containing all the installation
files, e.g. `2.313.0`. Under these directories are the shell scripts to
configure and run, e.g. `config.sh` and `run.sh`, but also a number of hidden
files, all starting with a dot `.` containing the configuration (also live
configuration of the runner). For example, `.runner` seems to contain part of
the configuration and `.path` and `.env` being the files that seed (or are) the
files pointed at by the `GITHUB_PATH` and `GITHUB_ENV` environment variables.

The hosted tool cache is at `/opt/hostedtoolcache`. It is owned by the
`runner:docker` user:group pair. There is also a `/opt/actionarchivecache`, same
user:group pair.
