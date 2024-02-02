# Notes

## Installation

To install [krunvm] on Fedora, do as per the [instructions].

  [krunvm]: https://github.com/containers/krunvm
  [instructions]: https://github.com/containers/krunvm?tab=readme-ov-file#fedora

## Running

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

## Podman

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
