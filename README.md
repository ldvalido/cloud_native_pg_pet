# CloudNativePG Lab

Local Kubernetes lab implementing [ADR-010](docs/ADR-010.md): a production-grade PostgreSQL platform on Kubernetes using [CloudNativePG](https://cloudnative-pg.io/).

## Architecture

- **3-instance HA cluster** — 1 primary (read-write) + 2 replicas (HA + future read scaling)
- **Automatic failover** managed by the CloudNativePG operator
- **High-write optimised** PostgreSQL parameters (WAL, checkpoints, autovacuum)
- **Query observability** via `pg_stat_statements`
- **Adminer** for local database access
- **GitOps-ready** Kustomize structure, Tilt for local development

> **Lab vs production:** Storage is set to 3Gi (operator volumes) and 1Gi (WAL). Production values from ADR-010 are 100–200GiB data + proportional WAL. WAL parameters are scaled accordingly.

## Repository structure

```
.
├── Tiltfile                   # Local dev orchestration (Tilt)
├── Makefile                   # Lifecycle and operational targets
├── kustomization.yaml         # Root Kustomize entrypoint
├── operator/
│   ├── kustomization.yaml     # Applies vendored operator manifest
│   └── cnpg-1.25.1.yaml      # ⚠ Vendored — see note below (gitignored)
└── cluster/
    ├── kustomization.yaml
    ├── 00-namespace.yaml      # postgres namespace
    ├── 01-storageclass.yaml   # SSD StorageClass (postgres-ssd)
    ├── 02-superuser-secret.yaml
    ├── 03-app-secret.yaml
    ├── 04-cluster.yaml        # CloudNativePG Cluster (main resource)
    └── 05-adminer.yaml        # Adminer deployment + NodePort service
```

## Prerequisites

| Tool | Version |
|---|---|
| kubectl | ≥ 1.28 |
| kustomize | ≥ 5.0 (or via `kubectl -k`) |
| tilt | ≥ 0.33 |
| curl | any |
| A local Kubernetes cluster | k3s, Rancher Desktop, Docker Desktop, kind… |

## ⚠ Vendored operator manifest

`operator/cnpg-1.25.1.yaml` is **gitignored** because it is large (~1MB) and fully reproducible. Before running anything, download it once:

```bash
make operator-vendor
```

This fetches the pinned CloudNativePG v1.25.1 release manifest from GitHub and saves it to `operator/cnpg-1.25.1.yaml`. Every developer or CI runner cloning the repo must run this step first.

To upgrade the operator version, change `CNPG_VERSION` in the Makefile and re-run `make operator-vendor`.

## Quick start (Tilt — recommended)

```bash
# 1. Download the vendored operator manifest (once per clone)
make operator-vendor

# 2. Start Tilt — installs operator, deploys cluster, opens port-forward
make tilt-up
```

Tilt watches all files under `operator/` and `cluster/`. Any saved change is automatically re-applied to the cluster.

**Adminer** is available at [http://localhost:8080](http://localhost:8080) as soon as the cluster is ready.

| Field | Value |
|---|---|
| System | PostgreSQL |
| Server | `pg-lab-rw` *(pre-filled)* |
| Username | `app` / `postgres` |
| Password | value from `cluster/02-superuser-secret.yaml` |
| Database | `app` |

```bash
# Stop Tilt and remove all resources
make tilt-down
```

## Manual lifecycle (without Tilt)

```bash
make operator-vendor   # download operator manifest
make install           # operator + wait + cluster
make status            # check cluster health
make delete            # remove cluster + operator (PVCs kept)
```

## Operational targets

All targets below work alongside Tilt at any time.

```bash
make status            # Cluster status + pod summary
make pods              # All pods in the postgres namespace
make events            # Recent namespace events (newest last)

make logs              # Stream logs from all cluster pods
make logs-primary      # Stream logs from the current primary only

make psql              # psql shell on the primary (read-write)
make psql-ro           # psql shell on a replica (read-only)

make cluster-restart   # Rolling restart of the cluster
make backup-list       # List ScheduledBackups and Backups
```

## StorageClass

`cluster/01-storageclass.yaml` defaults to `rancher.io/local-path` (k3s / Rancher Desktop). Adjust the `provisioner` field for your environment:

| Environment | Provisioner |
|---|---|
| k3s / Rancher Desktop | `rancher.io/local-path` |
| Docker Desktop | `docker.io/hostpath` |
| AWS EKS | `ebs.csi.aws.com` |
| GKE | `pd.csi.storage.gke.io` |
| Azure AKS | `disk.csi.azure.com` |

## Secrets

Secrets use plaintext `stringData` for lab convenience. **Replace all placeholder passwords before applying to any shared or production environment.** For production, integrate [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) or [External Secrets Operator](https://external-secrets.io/).

## CloudNativePG services

The operator creates three services automatically:

| Service | Target | Use |
|---|---|---|
| `pg-lab-rw` | Primary only | Reads + writes |
| `pg-lab-ro` | Replicas only | Read offloading |
| `pg-lab-r` | All instances | Any connection |

## Backup

The backup block in `cluster/04-cluster.yaml` is present but commented out. To activate:

1. Create an S3-compatible bucket and credentials secret
2. Uncomment and fill the `backup:` section in `04-cluster.yaml`
3. Re-apply (`make cluster-install` or save the file under Tilt)

## Roadmap

- [ ] Phase 2 — Observability: VictoriaMetrics (PodMonitor already wired), VictoriaLogs via Vector, Grafana dashboards
- [ ] Phase 2 — Alerting: vmalert rules (disk, replication lag, WAL growth, primary unavailable)
- [ ] Phase 2 — Tracing: Jaeger integration at the application level
- [ ] Phase 3 — PgBouncer connection pooling
- [ ] Phase 3 — Backup activation (Barman + S3 + PITR)
- [ ] Phase 4 — Partition lifecycle automation
