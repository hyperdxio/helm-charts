# ClickStack Helm Charts

---

## ⚠️ REPOSITORY MIGRATION NOTICE

**Active development has been migrated to the [ClickStack Helm Charts repository](https://github.com/ClickHouse/ClickStack-helm-charts).**

This repository will remain available as **read-only** for historical reference, but **no new releases will be published here**. All future updates, bug fixes, and features will be available only in the new repository.

### Migrating Existing Installations

If you have an existing installation using this repository, please update your Helm configuration to point to the new repository:

```bash
# Add the new repository
helm repo add clickstack https://clickhouse.github.io/ClickStack-helm-charts

# Update your repository list
helm repo update

# Upgrade your existing installation to use the new repository
# Replace 'my-release' with your actual release name
helm upgrade my-release clickstack/clickstack

# (Optional) Remove the old repository reference
helm repo remove <old-repo-name>
```

For more information and the latest releases, visit: **https://github.com/ClickHouse/ClickStack-helm-charts**

---

**ClickStack** is an open-source observability stack combining ClickHouse, HyperDX, and OpenTelemetry for logs, metrics, and traces.

## Quick Start
```bash
helm repo add clickstack https://clickhouse.github.io/ClickStack-helm-charts
helm repo update
helm install my-clickstack clickstack/clickstack
```

For configuration, cloud deployment, ingress setup, and troubleshooting, see the [official documentation](https://clickhouse.com/docs/use-cases/observability/clickstack/deployment/helm).

## Charts

- **`clickstack/clickstack`** (v1.0.0+) - Recommended for all deployments
- **`clickstack/hdx-oss-v2`** (v0.8.4) - Legacy (migrate to `clickstack`)

## Support

- **[Documentation](https://clickhouse.com/docs/use-cases/observability/clickstack)** - Installation, configuration, guides
- **[Issues](https://github.com/ClickHouse/ClickStack-helm-charts/issues)** - Report bugs or request features
