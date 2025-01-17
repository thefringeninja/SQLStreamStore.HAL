ARG CONTAINER_RUNTIME_VERSION=2.2.6
ARG CONTAINER_RUNTIME=alpine3.9

FROM node:10.12.0-alpine AS build-javascript
ARG CLIENT_PACKAGE=@thefringeninja/browser
ARG CLIENT_VERSION=0.9.4
ARG NPM_REGISTRY=npm.pkg.github.com
ARG GITHUB_TOKEN

ENV REACT_APP_CLIENT_VERSION=${CLIENT_VERSION}

WORKDIR /app

COPY .npmrc .npmrc

RUN yarn init --yes && \
    yarn add ${CLIENT_PACKAGE}@${CLIENT_VERSION}

WORKDIR /app/node_modules/${CLIENT_PACKAGE}

RUN yarn && \
    yarn react-scripts-ts build && \
    echo ${CLIENT_VERSION} > /app/.clientversion

FROM mcr.microsoft.com/dotnet/core/sdk:2.2.401-stretch AS build-dotnet
ARG CLIENT_PACKAGE=@thefringeninja/browser
ARG RUNTIME=alpine-x64
ARG LIBRARY_VERSION=1.2.0

WORKDIR /app

COPY ./*.sln ./

WORKDIR /app/src

COPY ./src/*/*.csproj ./src/Directory.Build.props ./

RUN for file in $(ls *.csproj); do mkdir -p ./${file%.*}/ && mv $file ./${file%.*}/; done

WORKDIR /app/tests

COPY ./tests/*/*.csproj ./

RUN for file in $(ls *.csproj); do mkdir -p ./${file%.*}/ && mv $file ./${file%.*}/; done

WORKDIR /app

RUN dotnet restore --runtime=${RUNTIME}

WORKDIR /app/src

COPY ./src .

COPY --from=build-javascript /app/node_modules/${CLIENT_PACKAGE}/build /app/src/SqlStreamStore.Server/Browser/build

WORKDIR /app/tests

COPY ./tests .

WORKDIR /app/build

COPY ./build/build.csproj .

RUN dotnet restore

COPY ./build .

WORKDIR /app/src

COPY ./src .

WORKDIR /app

COPY ./*.sln .git ./

RUN dotnet tool install --global --version=2.0.0 minver-cli && /root/.dotnet/tools/minver > .version

RUN dotnet run --project build/build.csproj -- --runtime=${RUNTIME} --library-version=${LIBRARY_VERSION}

FROM mcr.microsoft.com/dotnet/core/runtime-deps:${CONTAINER_RUNTIME_VERSION}-${CONTAINER_RUNTIME} AS runtime

WORKDIR /app

COPY --from=build-dotnet /app/publish /app/.version ./

ENTRYPOINT ["/app/SqlStreamStore.Server"]
