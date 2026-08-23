FROM ubuntu:24.04

ARG NODE_MAJOR=22
ARG IWE_VERSION=0.20.0
ARG IWE_SOURCE=npm

ENV DEBIAN_FRONTEND=noninteractive
ENV IWE_EVAL_APP=/app
ENV IWE_EVAL_LOGS=/logs
ENV IWE_EVAL_SKILLS=/opt/iwe-skills
ENV IWE_EVAL_TOOLS=/opt/iwe-evals

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git jq make gnupg asciinema tmux \
    && curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN if [ "$IWE_SOURCE" = "npm" ]; then \
      npm install --global @iwe-org/iwe@${IWE_VERSION} && iwe --version; \
    fi

RUN git config --system --add safe.directory /app

COPY . /opt/iwe-skills

RUN if [ "$IWE_SOURCE" = "copy" ]; then \
      install -m 0755 /opt/iwe-skills/evals/harbor/image/bin/iwe /usr/local/bin/iwe \
      && iwe --version; \
    fi

RUN mkdir -p /opt/iwe-evals \
    && cp /opt/iwe-skills/evals/harbor/lib/assert.sh /opt/iwe-evals/assert.sh \
    && cp /opt/iwe-skills/evals/harbor/image/setup-lib.sh /opt/iwe-evals/setup-lib.sh \
    && cp /opt/iwe-skills/evals/harbor/image/marker.sh /opt/iwe-evals/marker.sh \
    && cp -R /opt/iwe-skills/evals/harbor/image/fixtures /opt/iwe-evals/fixtures \
    && chmod +x /opt/iwe-evals/marker.sh

RUN sh /opt/iwe-skills/evals/harbor/image/build-fixture.sh /app /opt/iwe-skills \
    && git -C /app log --oneline

RUN mkdir -p /logs/agent /logs/verifier /logs/artifacts

WORKDIR /app
