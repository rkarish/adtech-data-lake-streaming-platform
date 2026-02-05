FROM apache/superset:latest

USER root
RUN /app/docker/pip-install.sh trino psycopg2-binary debugpy

USER superset
