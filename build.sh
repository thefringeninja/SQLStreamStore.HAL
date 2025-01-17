#!/usr/bin/env bash

set -e

CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-alpine3.9}
LIBRARY_VERSION=${LIBRARY_VERSION:-1.2.0-beta.8}
CLIENT_VERSION=${CLIENT_VERSION:-0.9.4}
NPM_REGISTRY=${NPM_REGISTRY:-npm.pkg.github.com}

LOCAL_IMAGE="sql-stream-store-server"
LOCAL="${LOCAL_IMAGE}:latest"

REMOTE_IMAGE="ghcr.io/thefringeninja/sqlstreamstore-server"

npm config set @thefringeninja:registry "https://${NPM_REGISTRY}" --location=project && \
  npm config set "//${NPM_REGISTRY}/:_authToken" $GITHUB_TOKEN --location=project

docker build \
    --build-arg CONTAINER_RUNTIME_VERSION=${CONTAINER_RUNTIME_VERSION:-2.2.6} \
    --build-arg CONTAINER_RUNTIME=${CONTAINER_RUNTIME} \
    --build-arg RUNTIME=${RUNTIME:-alpine-x64} \
    --build-arg LIBRARY_VERSION=${LIBRARY_VERSION} \
    --build-arg CLIENT_VERSION=${CLIENT_VERSION} \
    --secret id=GITHUB_TOKEN \
    --tag ${LOCAL} \
    .

SEMVER_REGEX="^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(\\-[0-9A-Za-z-]+(\\.[0-9A-Za-z-]+)*)?(\\+[0-9A-Za-z-]+(\\.[0-9A-Za-z-]+)*)?$"

[[ $LIBRARY_VERSION =~ $SEMVER_REGEX ]]

MAJOR_MINOR="${REMOTE_IMAGE}:${BASH_REMATCH[1]}.${BASH_REMATCH[2]}-${CONTAINER_RUNTIME}"
MAJOR_MINOR_PATCH="${REMOTE_IMAGE}:${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}-${CONTAINER_RUNTIME}"
MAJOR_MINOR_PATCH_PRE="${REMOTE_IMAGE}:${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}${BASH_REMATCH[4]}-${CONTAINER_RUNTIME}"

if [[ -z ${BASH_REMATCH[4]} ]]; then
    echo "Detected a tag with no prerelease."
    docker tag $LOCAL $MAJOR_MINOR_PATCH
    docker tag $LOCAL $MAJOR_MINOR
else
    echo "Detected a prerelease."
    docker tag $LOCAL $MAJOR_MINOR_PATCH_PRE
fi

docker images --filter=reference="${REMOTE_IMAGE}"
