# sind-action

GitHub Action to install [sind](https://github.com/GSI-HPC/sind) and manage
Slurm-in-Docker clusters in CI.

## Usage

```yaml
jobs:
  slurm-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      - uses: GSI-HPC/sind-action@v2
        with:
          clusters: |
            - test/cluster.yml

      - name: Run Slurm tests
        run: |
          sind exec -- sinfo
          sind exec -- srun hostname

      - uses: GSI-HPC/sind-action/cleanup@v2
        if: always()
```

## Requirements

- A Linux x64 or ARM64 runner, such as `ubuntu-latest` or `ubuntu-24.04-arm`.
  The action installs the sind binary for the runner's architecture. ARM64
  runners need sind v0.10.0 or later, the first release with linux/arm64
  binaries and node images.
- Docker and cgroup v2, which `sind doctor` checks before any cluster is
  created.
- `bash`, `curl`, `jq` and [mikefarah `yq`](https://github.com/mikefarah/yq) v4.

GitHub's Ubuntu runners meet all of these.

## Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `version` | sind version to install (e.g. `v0.9.0`; minimum `v0.8.0`) | `latest` |
| `clusters` | YAML list of cluster definitions (see below) | — |
| `pull` | Pull container images before creating | `true` |
| `realm` | sind realm for resource isolation (a DNS label, see below) | — |

### Cluster definitions

Each entry in `clusters` is either a **filepath** to a sind cluster config or
an **inline** cluster config. Each entry creates one cluster via
`sind create cluster --config <file>`, and the cluster's status is printed right
after it is created.

```yaml
clusters: |
  - test/cluster.yml
  - kind: Cluster
    name: dev
    nodes:
      - controller
      - worker: 3
```

## Outputs

| Output | Description |
|--------|-------------|
| `clusters` | Comma-separated list of created cluster names |
| `version` | Installed sind version |

## Cleanup

Use the cleanup sub-action to tear down clusters after your tests:

```yaml
- uses: GSI-HPC/sind-action/cleanup@v2
  if: always()
```

This deletes all clusters (within the configured `realm`, if one is set).

## Parallel Jobs with Realm Isolation

Use `realm` to isolate clusters when running multiple jobs on the same runner.
A realm name must be a single DNS label: lowercase letters, digits and `-`, 1 to
63 characters, not beginning or ending with `-`. sind v0.10.0 and later reject
other names, such as `Unit`, `unit_tests` or `ubuntu-24.04`, so pick matrix values
that fit or map them to a valid name.

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        suite: [unit, integration, e2e]
    steps:
      - uses: actions/checkout@v7

      - uses: GSI-HPC/sind-action@v2
        with:
          realm: ${{ matrix.suite }}
          clusters: |
            - cluster.yml

      - run: make test-${{ matrix.suite }}

      - uses: GSI-HPC/sind-action/cleanup@v2
        if: always()
```

## Slurm Versions

Clusters use sind's default node image, `ghcr.io/gsi-hpc/sind-node:latest`, which
carries the newest supported Slurm release line. sind also publishes an image per
supported release line, tagged `<YY>.<MM>` (e.g. `25.11`). To pin a release line,
or test against several, set the image in the cluster config:

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        slurm: ['25.11', '26.05']
    steps:
      - uses: actions/checkout@v7

      - uses: GSI-HPC/sind-action@v2
        with:
          clusters: |
            - kind: Cluster
              name: dev
              defaults:
                image: ghcr.io/gsi-hpc/sind-node:${{ matrix.slurm }}
              nodes:
                - controller
                - worker: 2

      - run: sind exec dev -- srun -N2 hostname

      - uses: GSI-HPC/sind-action/cleanup@v2
        if: always()
```

See [Official images](https://gsi-hpc.github.io/sind/container-images/building-images/#official-images)
for the available tags.

## AI disclosure

This project is developed with the help of AI coding tools. Since September 2026,
changes written by Anthropic's Claude Code agent are committed as
`Claude <noreply@anthropic.com>` and/or carry a `Co-Authored-By: Claude …` trailer;
earlier AI-assisted commits are not individually marked.

---

Copyright (c) 2026 GSI Helmholtzzentrum fuer Schwerionenforschung GmbH.
Licensed under the [MIT License](LICENSE).
