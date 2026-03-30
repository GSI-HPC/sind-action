# sind-action

GitHub Action to install [sind](https://github.com/GSI-HPC/sind) and manage
Slurm-in-Docker clusters in CI.

## Usage

```yaml
jobs:
  slurm-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6

      - uses: GSI-HPC/sind-action@v1
        with:
          clusters: |
            - test/cluster.yml

      - name: Run Slurm tests
        run: |
          sind exec -- sinfo
          sind exec -- srun hostname

      - uses: GSI-HPC/sind-action/cleanup@v1
        if: always()
```

## Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `version` | sind version to install (e.g. `v0.1.0`) | `latest` |
| `clusters` | YAML list of cluster definitions (see below) | — |
| `pull` | Pull container images before creating | `true` |
| `realm` | sind realm for resource isolation | — |

### Cluster definitions

Each entry in `clusters` is either a **filepath** to a sind cluster config or
an **inline** cluster config. Each entry creates one cluster via
`sind create cluster --config <file>`.

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
- uses: GSI-HPC/sind-action/cleanup@v1
  if: always()
```

This shows the cluster status (useful for debugging failures) and deletes all
clusters.

## Parallel Jobs with Realm Isolation

Use `realm` to isolate clusters when running multiple jobs on the same runner:

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        suite: [unit, integration, e2e]
    steps:
      - uses: actions/checkout@v6

      - uses: GSI-HPC/sind-action@v1
        with:
          realm: ${{ matrix.suite }}
          clusters: |
            - cluster.yml

      - run: make test-${{ matrix.suite }}

      - uses: GSI-HPC/sind-action/cleanup@v1
        if: always()
```

---

Copyright (c) 2026 GSI Helmholtzzentrum fuer Schwerionenforschung GmbH.
Licensed under the [MIT License](LICENSE).
