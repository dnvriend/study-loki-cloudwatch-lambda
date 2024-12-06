FROM public.ecr.aws/bitnami/grafana:latest

USER root

RUN install_packages python3 python3-pip awscli netcat-traditional && \
    pip3 install boto3 requests --break-system-packages && \
    grafana cli plugins install grafana-athena-datasource && \
    grafana cli plugins install grafana-simple-json-datasource

USER 1001

ENTRYPOINT ["/bin/sh", "-c", "/opt/bitnami/scripts/grafana/run.sh"]
