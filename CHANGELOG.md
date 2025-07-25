# helm-charts

## 0.6.8

### Patch Changes

- 9db1d33: fix: rename CRON_IN_APP_DISABLED to RUN_SCHEDULED_TASKS_EXTERNALLY

## 0.6.7

### Patch Changes

- c2ffc45: chore: Update appVersion to 2.0.6
- c0d70d5: fix: update the new entrypoint since v2.0.2 (alert cronjob)

## 0.6.6

### Patch Changes

- b6ab8ff: feat: support set replica and resources for otel-collector
- f9c8a4c: feat: improve availability of HyperDX pods

## 0.6.5

### Patch Changes

- 40f2e89: feat: support servicetype and annotations for clickhouse svc

## 0.6.4

### Patch Changes

- d8ca4db: chore: Remove NEXT_PUBLIC_URL from configmap as it is not needed
- 46a37c6: feat: support nodeSelector and toleration
- b5881bd: fix: Update FRONTEND_URL to be dynamic w/ingress
- b82c57d: fix: Allow for configurable service type + annotations

## 0.6.3

### Patch Changes

- 39d37c5: fix if condition typo
- 3d75672: fix: Fix pathType for ingress

## 0.6.2

### Patch Changes

- d0650ed: Allows setting custom ingressClassName and annotations for the HyperDX application ingress.

## 0.6.1

### Patch Changes

- c117d72: fix: Allow for custom otel collector environment variables

## 0.6.0

### Minor Changes

- 7b964f1: Allow defining additional ingresses so resources outside of the HyperDX application can accept traffic outside of the cluster.
- 1541c5f: feat: refactor image value + bump default tag to 2.0.0

### Patch Changes

- cec5983: enable using remote mongodb

## 0.5.2

### Patch Changes

- 9493843: fix: relocate mongodb volume persistence field + handle the case when CH pvc is disabled
- 4e246da: feat: add 'clickhouseUser' and 'clickhousePassword' otel settings
- 8608668: chore: Remove snapshot tests and replace with assertions
