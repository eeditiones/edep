# START STAGE 1
FROM openjdk:8-jdk-slim as builder

USER root

ENV ANT_VERSION 1.10.12
ENV ANT_HOME /etc/ant-${ANT_VERSION}

WORKDIR /tmp

RUN apt-get update && apt-get install -y \
    git \
    curl


RUN curl -sL https://deb.nodesource.com/setup_14.x | bash - \
    && apt-get install -y nodejs \
    && curl -L https://www.npmjs.com/install.sh | sh


RUN curl -L -o apache-ant-${ANT_VERSION}-bin.tar.gz http://www.apache.org/dist/ant/binaries/apache-ant-${ANT_VERSION}-bin.tar.gz \
    && mkdir ant-${ANT_VERSION} \
    && tar -zxvf apache-ant-${ANT_VERSION}-bin.tar.gz \
    && mv apache-ant-${ANT_VERSION} ${ANT_HOME} \
    && rm apache-ant-${ANT_VERSION}-bin.tar.gz \
    && rm -rf ant-${ANT_VERSION} \
    && rm -rf ${ANT_HOME}/manual \
    && unset ANT_VERSION

ENV PATH ${PATH}:${ANT_HOME}/bin

FROM builder as tei

ARG TEMPLATING_VERSION=1.0.2
ARG PUBLISHER_LIB_VERSION=2.10.0
ARG ROUTER_VERSION=0.5.1
# replace with name of your edition repository and choose branch to build
ARG EDEP_VERSION=master

ARG GITLAB_USER

ARG GITLAB_PASSWORD


# add key
RUN  mkdir -p ~/.ssh && ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts

# Replace git URL below to point to your git repository 
RUN  git clone https://${GITLAB_USER}:${GITLAB_PASSWORD}@gitlab.existsolutions.com/akademie-mainz/edep.git \
    # replace my-edition with name of your app
    && cd edep \
    && echo Checking out ${EDEP_VERSION} \
    && git checkout ${EDEP_VERSION} \
    && ant

RUN git clone https://${GITLAB_USER}:${GITLAB_PASSWORD}@gitlab.existsolutions.com/akademie-mainz/edep-data.git \
    && cd edep-data \
    && ant

RUN curl -L -o /tmp/oas-router-${ROUTER_VERSION}.xar http://exist-db.org/exist/apps/public-repo/public/oas-router-${ROUTER_VERSION}.xar
RUN curl -L -o /tmp/tei-publisher-lib-${PUBLISHER_LIB_VERSION}.xar http://exist-db.org/exist/apps/public-repo/public/tei-publisher-lib-${PUBLISHER_LIB_VERSION}.xar
RUN curl -L -o /tmp/templating-${TEMPLATING_VERSION}.xar http://exist-db.org/exist/apps/public-repo/public/templating-${TEMPLATING_VERSION}.xar

FROM eclipse-temurin:11-jre-alpine

ARG EXIST_VERSION=6.2.0

RUN apk add curl

RUN curl -L -o /tmp/exist-distribution-${EXIST_VERSION}-unix.tar.bz2 https://github.com/eXist-db/exist/releases/download/eXist-${EXIST_VERSION}/exist-distribution-${EXIST_VERSION}-unix.tar.bz2 \
    && tar xfj /tmp/exist-distribution-${EXIST_VERSION}-unix.tar.bz2 -C /tmp \
    && rm /tmp/exist-distribution-${EXIST_VERSION}-unix.tar.bz2 \
    && mv /tmp/exist-distribution-${EXIST_VERSION} /exist

# replace edep with name of your app
COPY --from=tei /tmp/edep/dist/*.xar /exist/autodeploy/
COPY --from=tei /tmp/edep-data/build/*.xar /exist/autodeploy/
COPY --from=tei /tmp/*.xar /exist/autodeploy/

WORKDIR /exist

ARG ADMIN_PASS=none

ARG HTTP_PORT=8080
ARG HTTPS_PORT=8443

ENV NER_ENDPOINT=http://localhost:8001
ENV CONTEXT_PATH=auto

ENV JAVA_OPTS \
    -Djetty.port=${HTTP_PORT} \
    -Djetty.ssl.port=${HTTPS_PORT} \
    -Dfile.encoding=UTF8 \
    -Dsun.jnu.encoding=UTF-8 \
    -XX:+UseG1GC \
    -XX:+UseStringDeduplication \
    -XX:+UseContainerSupport \
    -XX:MaxRAMPercentage=${JVM_MAX_RAM_PERCENTAGE:-75.0} \ 
    -XX:+ExitOnOutOfMemoryError

# pre-populate the database by launching it once
RUN bin/client.sh -l --no-gui --xpath "system:get-version()"

RUN if [ "${ADMIN_PASS}" != "none" ]; then bin/client.sh -l --no-gui --xpath "sm:passwd('admin', '${ADMIN_PASS}')"; fi

EXPOSE ${HTTP_PORT}

ENTRYPOINT JAVA_OPTS="${JAVA_OPTS} -Dteipublisher.ner-endpoint=${NER_ENDPOINT} -Dteipublisher.context-path=${CONTEXT_PATH}" /exist/bin/startup.sh