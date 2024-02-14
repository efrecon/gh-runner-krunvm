# krunvm-based GitHub Runner(s)

This project creates one or several (ephemeral) GitHub [self-hosted][self] [runners] based on [krunvm]. [krunvm] creates so-called [microVM]s, and this provides fully isolated [runners] inside your infrastruture, as opposed to solutions based on Kubernetes or Docker containers.

  [self]: https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners
  [runners]: https://docs.github.com/en/actions/using-github-hosted-runners/about-github-hosted-runners/about-github-hosted-runners
  [krunvm]: https://github.com/containers/krunvm
  [microVM]: https://github.com/infracloudio/awesome-microvm
