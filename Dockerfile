# Copyright (c) Jupyter Development Team.
# Distributed under the terms of the Modified BSD License.
ARG REGISTRY=quay.io
ARG OWNER=jupyter
# See https://github.com/jupyter/docker-stacks/tree/main?tab=readme-ov-file#using-old-images
ARG TAG=00987883e58d 
ARG BASE_CONTAINER=$REGISTRY/$OWNER/scipy-notebook:$TAG
FROM $BASE_CONTAINER

ARG DBS_ROOT_CACERT_URL="https://mycoolartifactory.s3.ap-southeast-1.amazonaws.com/dbs-certs/dbs_cert.cer"
ARG DBS_ENTSUB_CACERT_URL="https://mycoolartifactory.s3.ap-southeast-1.amazonaws.com/dbs-certs/dbs_ent_sub.cer"

LABEL maintainer="Jupyter Project <jupyter@googlegroups.com>"

# Fix: https://github.com/hadolint/hadolint/wiki/DL4006
# Fix: https://github.com/koalaman/shellcheck/wiki/SC3014
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root

# Spark dependencies
# Default values can be overridden at build time
# (ARGS are in lowercase to distinguish them from ENV)
ARG openjdk_version="11"

RUN apt-get update --yes && \
    apt-get install --yes --no-install-recommends \
    "openjdk-${openjdk_version}-jre-headless" \
    ca-certificates-java && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# If spark_version is not set, latest stable Spark will be installed
ARG spark_version="3.5.2"
ARG hadoop_version="3"
# If scala_version is not set, Spark without Scala will be installed
ARG scala_version="2.13"
# URL to use for Spark downloads
# Recent versions: https://dlcdn.apache.org/spark/"
# You need to use https://archive.apache.org/dist/spark/ website if you want to download old Spark versions
# But it seems to be slower, that's why we use the recommended site for download
ARG spark_download_url="https://archive.apache.org/dist/spark/"

ENV SPARK_HOME=/usr/local/spark
ENV PATH="${PATH}:${SPARK_HOME}/bin"
ENV SPARK_OPTS="--driver-java-options=-Xms1024M --driver-java-options=-Xmx4096M --driver-java-options=-Dlog4j.logLevel=info"


COPY setup_spark.py /opt/setup-scripts/

RUN chmod 771 /opt/setup-scripts/setup_spark.py

# Setup Spark
RUN /opt/setup-scripts/setup_spark.py \
    --spark-version="${spark_version}" \
    --hadoop-version="${hadoop_version}" \
    --scala-version="${scala_version}" \
    --spark-download-url="${spark_download_url}"

# Configure IPython system-wide
COPY ipython_kernel_config.py "/etc/ipython/"
RUN fix-permissions "/etc/ipython/"

## Download DBS certificates to /etc/ssl/certs
RUN wget $DBS_ROOT_CACERT_URL  --output-document=/etc/ssl/certs/dbs_cert.crt
RUN wget $DBS_ENTSUB_CACERT_URL --output-document=/etc/ssl/certs/dbs_ent_sub.cer

# Download DBS certificates to /usr/share/ca-certificates
RUN wget $DBS_ROOT_CACERT_URL --output-document=/usr/local/share/ca-certificates/dbs_cert.crt
RUN wget $DBS_ENTSUB_CACERT_URL --output-document=/usr/local/share/ca-certificates/dbs_ent_sub.crt

# Update the ca-bundle
RUN sudo update-ca-certificates

USER ${NB_UID}

# Install pyarrow
# NOTE: It's important to ensure compatibility between Pandas versions.
# The pandas version in this Dockerfile should match the version
# on which the Pandas API for Spark is built.
# To find the right version:
# 1. Check out the Spark branch you are on: <https://github.com/apache/spark>
# 2. Find the pandas version in the file `dev/infra/Dockerfile`.
RUN mamba install --yes \
    'grpcio-status' \
    'grpcio' \
    'pandas=2.0.3' \
    'pyarrow' && \
    mamba clean --all -f -y && \
    fix-permissions "${CONDA_DIR}" && \
    fix-permissions "/home/${NB_USER}"

RUN pip install \
  'ray==2.23.0' \
  'ray[serve]==2.23.0'

WORKDIR "${HOME}"
EXPOSE 4040
