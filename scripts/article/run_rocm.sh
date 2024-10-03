#!/bin/bash

set -ex

export MILABENCH_GPU_ARCH=rocm
export MILABENCH_WORDIR="$(pwd)/$MILABENCH_GPU_ARCH"

export MILABENCH_BASE="$MILABENCH_WORDIR/results"
export MILABENCH_VENV="$MILABENCH_WORDIR/env"
export BENCHMARK_VENV="$MILABENCH_WORDIR/results/venv/torch"

if [ -z "${MILABENCH_SOURCE}" ]; then
    export MILABENCH_CONFIG="$MILABENCH_WORDIR/milabench/config/standard.yaml"
else
    export MILABENCH_CONFIG="$MILABENCH_SOURCE/config/standard.yaml"
fi

ARGS="$@"

install_prepare() {
    mkdir -p $MILABENCH_WORDIR
    cd $MILABENCH_WORDIR

    virtualenv $MILABENCH_WORDIR/env

    if [ -z "${MILABENCH_SOURCE}" ]; then
        if [ ! -d "$MILABENCH_WORDIR/milabench" ]; then
            git clone https://github.com/mila-iqia/milabench.git
        fi
        export MILABENCH_SOURCE="$MILABENCH_WORDIR/milabench"
    fi

    . $MILABENCH_WORDIR/env/bin/activate
    pip install -e $MILABENCH_SOURCE

    
    #
    # Install milabench's benchmarks in their venv
    #
    # pip install torch --index-url https://download.pytorch.org/whl/rocm6.1
    # milabench pin --variant rocm --from-scratch $ARGS 
    milabench install $ARGS 

    #
    # Override/add package to milabench venv here
    #
    which pip
    pip uninstall pynvml

    (
        . $BENCHMARK_VENV/bin/activate

        if [ -z "${MILABENCH_HF_TOKEN}" ]; then
            echo "Missing token"
        else
            huggingface-cli login --token $MILABENCH_HF_TOKEN
        fi

        #
        # Override/add package to the benchmark venv here
        #
        which pip
        # pip uninstall torch torchvision torchaudio -y
        # pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/rocm6.1
        # pip uninstall pynvml

        # sudo apt-get install lld
        # https://github.com/ROCm/jax/releases/tag/rocm-jaxlib-v0.4.30
        # does not really work
        pip install https://github.com/ROCm/jax/releases/download/rocm-jaxlib-v0.4.30/jaxlib-0.4.30+rocm611-cp310-cp310-manylinux2014_x86_64.whl
        pip install https://github.com/ROCm/jax/archive/refs/tags/rocm-jaxlib-v0.4.30.tar.gz

        # 
        FORCE_CUDA=1 pip install -U -v --no-build-isolation git+https://github.com/rusty1s/pytorch_cluster.git
        FORCE_CUDA=1 pip install -U -v --no-build-isolation git+https://github.com/rusty1s/pytorch_scatter.git
        FORCE_CUDA=1 pip install -U -v --no-build-isolation git+https://github.com/rusty1s/pytorch_sparse.git

        # takes forever to compile
        # https://github.com/ROCm/xformers
        pip install -v -U --no-build-isolation --no-deps git+https://github.com/ROCm/xformers.git@develop#egg=xformers
        pip install -v -U --no-build-isolation --no-deps git+https://github.com/ROCm/flash-attention.git 
    )

    #
    #   Generate/download datasets, download models etc...
    #
    milabench prepare $ARGS 
}

if [ ! -d "$MILABENCH_WORDIR" ]; then
    install_prepare
else
    echo "Reusing previous install"
    . $MILABENCH_WORDIR/env/bin/activate
fi

cd $MILABENCH_WORDIR

#
#   Run the benchmakrs
milabench run $ARGS 

#
#   Display report
milabench report --runs $MILABENCH_WORDIR/results/runs
