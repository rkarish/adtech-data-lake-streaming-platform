#!/bin/bash
set -e

superset db upgrade

superset fab create-admin \
  --username admin \
  --firstname Admin \
  --lastname Admin \
  --email admin@localhost \
  --password password || true

superset init

superset run -h 0.0.0.0 -p 8088 --with-threads
