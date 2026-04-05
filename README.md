# symmfuzz-experiments

This repository provides a reproducible experiment dataset for stateful network protocol fuzzing, including target configurations, build/run automation, and evaluation scripts. The current target set focuses on TLS and QUIC, and also keeps dcmtk/live555/mosquitto as baseline plaintext services for cross-fuzzer comparison.

Currently supported baseline fuzzers: 

- AFLNet: use `-f aflnet`
- StateAFL: use `-f stateafl`
- SGFuzz: use `-f sgfuzz`
- FT-Net: use `-f ft`
- SymmFuzz(our own fuzzer): use `-f pingu`. $pingu$ is the program name of our fuzzer proposed in the paper SymmFuzz.

## Todo

# Limitations

# Folder structure

```
symmfuzz-experiments-folder
├── subjects: this folder contains all the different protocols included in this benchmark and
│   │         each protocol may have more than one implementations
│   └── TLS
│   │   └── OpenSSL
│   │       └── config.sh
│   │       └── ft-sink.yaml
│   │       └── ft-source.yaml
│   │       └── pingu.yaml
│   │       └── README.md
│   │       └── ...
│   └── QUIC
│   └── ...
└── scripts: this folder contains all the scripts and configuration files to run experiments, collect & analyze results
│   └── build-env.sh: this file builds the docker image **pingu-env-${fuzzer}** according to Dockerfile-env-${fuzzer} that contains the source and binaries of the fuzzer specified and all the dependencies
│   └── Dockerfile-env-${fuzzer}
│   └── Dockerfile-dev: this file specifies the docker image that contains all the fuzzer source codes, dependencies and development environments
│   └── build.sh: this file builds the image for fuzzing runtime, based on the image **pingu-env-${fuzzer}**, according to Dockerfile. Each target should be built in a separate docker image using different fuzzers, like the image for TLS/OpenSSL instrumented and fuzzed by AFLNet, the image will be **pingu-aflnet-tls-openssl**
│   └── Dockerfile: this file builds the fuzzing runtime environment. The built image may be repeatedly launched to evaluate the fuzzer several times
│   └── run.sh: this file launches the fuzzing runtime container based on the image built by build.sh
│   └── evaluate.sh: this file will builds and launches the evaluation container, based on Dockerfile-eval, which includes jupyter, matplotlib and other stuff. The container is named with **pingu-eval**
│   └── Dockerfile-eval
│   └── utils.sh
│   └── shortcut.sh: some shortcuts for frequently used commands with some secrets
└── README.md: this file
```

# Fuzzers

# Tutorial - Fuzzing TLS/OpenSSL server with [AFLNet](https://github.com/aflnet/aflnet)

Follow the steps below to run and collect experimental results for TLS/OpenSSL. The similar steps should be followed to run experiments on other subjects. Each subject program comes with a README.md file showing subject-specific commands to run experiments.#

## Prerequisites

- **Docker**: Make sure you have docker installed on your machine. If not, please refer to [Docker installation](https://docs.docker.com/get-docker/). The docker-engine that supports DOCKER_BUILDKIT=1 would be better, but it is not required.
- **Storage**: Also make sure you have enough storage space for the built images and the fuzzing results. Usually, the pingu-env image is over 1GB and the fuzzing runtime image is over 2GB, depending on the target program and the fuzzer.

For development purpose, you can build and launch a dedicated development environment for the fuzzing runtime. The container contains all the built fuzzing tool binaries. Note that the fuzzing target programs are not included. 

## Common Environments and build args

When doing docker stuff, including building and running, there are some common environments and build args that may be useful, especially when you are behind a proxy or in ZH_CN.

- **HTTP_PROXY**: The proxy for HTTP. When you are behind a proxy(e.g. Company proxy), you can set this environment variable.
- **HTTPS_PROXY**: The proxy for HTTPS.

## Step-1. Build the base image

First change the working directory to the root directory of the repository.

```sh
./scripts/build-env.sh -f aflnet
```

Arguments:
- ***-f*** : name of the fuzzer. Supports aflnet, stateafl, sgfuzz, ft, puffin, pingu.

The parameters specified after the **--** are the build arguments passed directly for the docker build command. You can specify sth like `--network=host --build-arg HTTP_PROXY=xxx`. Check the [Dockerfile-env-aflnet](scripts/Dockerfile-env-aflnet) to see the available build arguments.

## Step-2. Build the fuzzing runtime image

```sh
./scripts/build.sh -t TLS/OpenSSL -f ft -v 7b649c7
```

The parameters specified after the **--** are the build arguments passed directly for the docker build command. You can specify sth like `--network=host --build-arg HTTP_PROXY=xxx`. Check the [Dockerfile](scripts/Dockerfile) to see the available build arguments.

Arguments:
- ***-t / --target*** : name of the target implementation (e.g., TLS/OpenSSL). The name should be referenced in the subjects directory.
- ***-f / --fuzzer*** : name of the fuzzer. Supports aflnet, stateafl, sgfuzz, ft, puffin, pingu.
- ***-v / --version*** : the version of the target implementation. Tag names and commit hashes are supported.

## Step-3. Fuzz

```sh
./scripts/run.sh -t TLS/OpenSSL -f ft -v 7b649c7 --times 1 --timeout 60 -o output
```

Required arguments:
- ***-t / --target*** : name of the target implementation (e.g., TLS/OpenSSL). The name should be referenced in the subjects directory.
- ***-f / --fuzzer*** : name of the fuzzer. Supports aflnet, stateafl, sgfuzz, ft, puffin, pingu.
- ***-v / --version*** : the version of the target implementation. Tag names and commit hashes are supported.
- ***--times*** : number of runs. The count of runs means the count of the docker containers.
- ***--timeout*** : timeout for each run, in seconds, like 86400 for 24 hours.
- ***-o / --output*** : output directory

Options:
- ***--cleanup*** : automatically delete the container after the fuzzing process.
- ***--detached*** : wait for the container to exit in the background.

## Step-4. Analyze the results

```sh
./scripts/evaluate.sh -t TLS/OpenSSL -f ft -v 7b649c7 -o output -c 2
```
The parameters specified after the **--** are the build arguments passed directly for the docker build command. You can specify sth like `--network=host --build-arg HTTP_PROXY=xxx`. Check the [Dockerfile-eval](scripts/Dockerfile-eval) to see the available build arguments.

Required arguments:
- ***-t / --target*** : name of the target implementation (e.g., TLS/OpenSSL). The name should be referenced in the subjects directory.
- ***-f / --fuzzer*** : name of the fuzzer. Supports aflnet, stateafl, sgfuzz, ft, puffin, pingu.
- ***-v / --version*** : the version of the target implementation. Tag names and commit hashes are supported.
- ***-o / --output*** : the directory where the results are stored.
- ***-c / --count*** : the number of runs to be evaluated upon.


# Utility scripts


# Parallel builds

To speed-up the build of Docker images, you can pass the option "-j" to `make`, using the `MAKE_OPT` environment variable and the `--build-arg` option of `docker build`. Example:

```
export MAKE_OPT="-j4"
docker build . -t lightftp --build-arg MAKE_OPT
```

# FAQs

## 1. Q1

## 2. Q2

## 3. Q3

# Citing symmfuzz-experiments

# Citing ProFuzzBench

ProFuzzBench has been accepted for publication as a [Tool Demonstrations paper](https://dl.acm.org/doi/pdf/10.1145/3460319.3469077) at the 30th ACM SIGSOFT International Symposium on Software Testing and Analysis (ISSTA) 2021.

```
@inproceedings{profuzzbench,
  title={ProFuzzBench: A Benchmark for Stateful Protocol Fuzzing},
  author={Roberto Natella and Van-Thuan Pham},
  booktitle={Proceedings of the 30th ACM SIGSOFT International Symposium on Software Testing and Analysis},
  year={2021}
}
```
