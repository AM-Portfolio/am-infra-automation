# IAM-1 tests (dig)

- [ ] User **with** `access-grafana-editor` can edit dashboards; **without** cannot
- [ ] User **with** `access-minio-read` only cannot write objects; write group can
- [ ] User **without** `access-kafka-ui` denied; **with** reaches Provectus kafka-ui
- [ ] No Redpanda Console deploy; single `kafka-ui` release
