function checkout {
    if [ ! -d ".git-cache/dcmtk" ]; then
        git clone https://github.com/dcmtk/dcmtk.git .git-cache/dcmtk
    fi

    mkdir -p repo
    cp -r .git-cache/dcmtk repo/dcmtk

    pushd repo/dcmtk >/dev/null

    git pull
    git checkout 1549d8c
    git apply "${HOME}/profuzzbench/subjects/DICOM/dcmtk/ft-dcmtk.patch"
    git add .
    git commit -m "apply fuzzing patch"
    git rebase "$@"
    
    popd >/dev/null
}

function replay {
    ${HOME}/aflnet/aflnet-replay $1 DICOM 5158 1 &
    LD_PRELOAD=libgcov_preload.so:libfake_random.so:libfaketime.so.1 \
    FAKE_RANDOM=1 \
    FAKETIME_ONLY_CMDS="dcmqrscp" \
        timeout -k 0 -s SIGTERM 1s ${HOME}/target/gcov/consumer/dcmtk/build/bin/dcmqrscp --single-process --config ${HOME}/profuzzbench/subjects/DICOM/dcmtk/dcmqrscp.cfg
    wait

    pkill dcmqrscp
}

function replay_poc {
    ${HOME}/aflnet/aflnet-replay $1 DICOM 5158 1 &
    err_output=$(timeout -k 0 -s SIGTERM 1s ${HOME}/target/asan/dcmtk/build/bin/dcmqrscp --single-process --config ${HOME}/profuzzbench/subjects/DICOM/dcmtk/dcmqrscp.cfg > /dev/null)
    wait

    pkill dcmqrscp

    echo "$err_output"
}

function build_aflnet {
    mkdir -p target/aflnet
    rm -rf target/aflnet/*
    cp -r repo/dcmtk target/aflnet/dcmtk
    pushd target/aflnet/dcmtk >/dev/null

    export CC=${HOME}/aflnet/afl-clang-fast
    export CXX=${HOME}/aflnet/afl-clang-fast++
    export CFLAGS="-O3 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER -DASAN_REPORT_HOOK"
    export CXXFLAGS="-O3 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER -DASAN_REPORT_HOOK"
    export LDFLAGS="-fsanitize=address"

    mkdir build && cd build
    cmake ..
    make dcmqrscp ${MAKE_OPT}

    popd >/dev/null
}

function run_aflnet {
    replay_step=$1
    gcov_step=$2
    timeout=$3
    outdir=/tmp/fuzzing-output
    indir=${HOME}/profuzzbench/subjects/DICOM/dcmtk/in-dicom
    pushd ${HOME}/target/aflnet/dcmtk/build/bin >/dev/null

    mkdir -p $outdir

    if [ ! -d "${HOME}/ACME_STORE" ]; then
        mkdir ${HOME}/ACME_STORE
    fi

    export AFL_SKIP_CPUFREQ=1
    export AFL_PRELOAD=libfake_random.so:libfaketime.so.1
    export FAKETIME_ONLY_CMDS="dcmqrscp"
    export AFL_NO_AFFINITY=1
    export FAKE_RANDOM=1
    export ASAN_OPTIONS="abort_on_error=1:symbolize=1:detect_leaks=0:handle_abort=2:handle_segv=2:handle_sigbus=2:handle_sigill=2:detect_stack_use_after_return=0:detect_odr_violation=0"
    export DCMDICTPATH=${HOME}/profuzzbench/subjects/DICOM/dcmtk/dicom.dic
    export WORKDIR=${HOME}/target/aflnet/dcmtk/build/bin
    export ASAN_REPORT_PATH=${outdir}/replayable-crashes

    timeout -k 0 --preserve-status $timeout \
        ${HOME}/aflnet/afl-fuzz -d -i $indir \
        -o $outdir -N tcp://127.0.0.1/5158 \
        -P DICOM -D 10000 -q 3 -s 3 -E -K -R -W 50  -m none \
        -c ${HOME}/profuzzbench/subjects/DICOM/dcmtk/clean.sh \
        ./dcmqrscp --single-process --config ${HOME}/profuzzbench/subjects/DICOM/dcmtk/dcmqrscp.cfg

    cp /home/user/repo/dcmtk/dcmdata/libsrc/vrscanl.c /home/user/target/gcov/consumer/dcmtk
    cp /home/user/repo/dcmtk/dcmdata/libsrc/vrscanl.l /home/user/target/gcov/consumer/dcmtk
    cp /home/user/repo/dcmtk/dcmdata/libsrc/vrscanl.c /home/user/target/gcov/consumer/dcmtk/build/dcmdata/libsrc/CMakeFiles/dcmdata.dir
    cp /home/user/repo/dcmtk/dcmdata/libsrc/vrscanl.l /home/user/target/gcov/consumer/dcmtk/build/dcmdata/libsrc/CMakeFiles/dcmdata.dir
    
    cd ${HOME}/target/gcov/consumer/dcmtk
    list_cmd="ls -1 ${outdir}/replayable-queue/id* | awk 'NR % ${replay_step} == 0' | tr '\n' ' ' | sed 's/ $//'"
    clean_cmd="rm -f ${HOME}/ACME_STORE/*"

    compute_coverage replay "$list_cmd" "${gcov_step}" "${outdir}/coverage.csv" "" "$clean_cmd"
    mkdir -p ${outdir}/cov_html
    gcovr -r . --html --html-details -o ${outdir}/cov_html/index.html

    export ASAN_OPTIONS="abort_on_error=1:symbolize=1:detect_leaks=0:handle_abort=2:handle_segv=2:handle_sigbus=2:handle_sigill=2:detect_stack_use_after_return=0:detect_odr_violation=0"
    collect_asan_reports "/tmp/fuzzing-output/replayable-crashes" replay_poc "$clean_cmd"

    popd >/dev/null
}

function build_stateafl {
    mkdir -p target/stateafl
    rm -rf target/stateafl/*
    cp -r repo/dcmtk target/stateafl/dcmtk
    pushd target/stateafl/dcmtk >/dev/null

    git apply ${HOME}/profuzzbench/subjects/DICOM/dcmtk/buffer.patch

    export ASAN_OPTIONS=detect_leaks=0
    export CC=${HOME}/stateafl/afl-clang-fast
    export CXX=${HOME}/stateafl/afl-clang-fast++
    export CFLAGS="-O3 -g -fsanitize=address -DFT_FUZZING -DFT_CONSUMER -DASAN_REPORT_HOOK"
    export CXXFLAGS="-O3 -g -fsanitize=address -DFT_FUZZING -DFT_CONSUMER -DASAN_REPORT_HOOK"
    export LDFLAGS="-fsanitize=address"

    mkdir build && cd build
    cmake ..
    make dcmqrscp ${MAKE_OPT}
    
    rm -rf fuzz test .git doc

    popd >/dev/null
}

function run_stateafl {
    replay_step=$1
    gcov_step=$2
    timeout=$3
    outdir=/tmp/fuzzing-output
    indir=${HOME}/profuzzbench/subjects/DICOM/dcmtk/in-dicom-replay
    pushd ${HOME}/target/stateafl/dcmtk/build/bin >/dev/null

    mkdir -p $outdir

    if [ ! -d "${HOME}/ACME_STORE" ]; then
        mkdir ${HOME}/ACME_STORE
    fi

    export DCMDICTPATH=${HOME}/profuzzbench/subjects/DICOM/dcmtk/dicom.dic
    export AFL_SKIP_CPUFREQ=1
    export AFL_PRELOAD=libfake_random.so:libfaketime.so.1
    export FAKETIME_ONLY_CMDS="dcmqrscp"
    export AFL_NO_AFFINITY=1
    export FAKE_RANDOM=1
    export ASAN_OPTIONS="abort_on_error=1:symbolize=1:detect_leaks=0:handle_abort=2:handle_segv=2:handle_sigbus=2:handle_sigill=2:detect_stack_use_after_return=1:detect_odr_violation=0:detect_container_overflow=0:poison_array_cookie=0"
    export ASAN_REPORT_PATH=${outdir}/replayable-crashes

    timeout -k 0 --preserve-status $timeout \
        ${HOME}/stateafl/afl-fuzz -d -i $indir \
        -o $outdir -N tcp://127.0.0.1/5158 \
        -P DICOM -D 10000 -E -K -m none \
        -c ${HOME}/profuzzbench/subjects/DICOM/dcmtk/clean.sh \
        ./dcmqrscp --single-process --config ${HOME}/profuzzbench/subjects/DICOM/dcmtk/dcmqrscp.cfg

    cp /home/user/repo/dcmtk/dcmdata/libsrc/vrscanl.c /home/user/target/gcov/consumer/dcmtk
    cp /home/user/repo/dcmtk/dcmdata/libsrc/vrscanl.l /home/user/target/gcov/consumer/dcmtk
    cp /home/user/repo/dcmtk/dcmdata/libsrc/vrscanl.c /home/user/target/gcov/consumer/dcmtk/build/dcmdata/libsrc/CMakeFiles/dcmdata.dir
    cp /home/user/repo/dcmtk/dcmdata/libsrc/vrscanl.l /home/user/target/gcov/consumer/dcmtk/build/dcmdata/libsrc/CMakeFiles/dcmdata.dir

    cd ${HOME}/target/gcov/consumer/dcmtk
    list_cmd="ls -1 ${outdir}/replayable-queue/id* | awk 'NR % ${replay_step} == 0' | tr '\n' ' ' | sed 's/ $//'"
    clean_cmd="rm -f ${HOME}/ACME_STORE/*"
    compute_coverage replay "$list_cmd" ${gcov_step} ${outdir}/coverage.csv "" "$clean_cmd"

    mkdir -p ${outdir}/cov_html
    gcovr -r . --html --html-details -o ${outdir}/cov_html/index.html

    export ASAN_OPTIONS="abort_on_error=1:symbolize=1:detect_leaks=0:handle_abort=2:handle_segv=2:handle_sigbus=2:handle_sigill=2:detect_stack_use_after_return=0:detect_odr_violation=0"
    collect_asan_reports "/tmp/fuzzing-output/replayable-crashes" replay_poc "$clean_cmd"

    popd >/dev/null
}

function build_sgfuzz {
    mkdir -p target/sgfuzz
    rm -rf target/sgfuzz/*
    cp -r repo/dcmtk target/sgfuzz/dcmtk

    pushd target/sgfuzz/dcmtk >/dev/null

    export LLVM_COMPILER=clang
    export CC=wllvm
    export CXX=wllvm++
    export CFLAGS="-O0 -g -fno-inline-functions -fno-inline -fno-discard-value-names -fno-vectorize -fno-slp-vectorize -DFT_FUZZING -DSGFUZZ -v -Wno-int-conversion"
    export CXXFLAGS="-O0 -g -fno-inline-functions -fno-inline -fno-discard-value-names -fno-vectorize -fno-slp-vectorize -DFT_FUZZING -DSGFUZZ -v -Wno-int-conversion"

    export FT_BLOCK_PATH_POSTFIXES="libsrc/ofchrenc.cc"
    python3 $HOME/sgfuzz/sanitizer/State_machine_instrument.py . -b $HOME/profuzzbench/subjects/DICOM/dcmtk/blocked_variable
    
    mkdir build && cd build
    cmake ..

    make dcmqrscp ${MAKE_OPT}
    cd bin
    extract-bc dcmqrscp

    export SGFUZZ_USE_HF_MAIN=1
    export SGFUZZ_PATCHING_TYPE_FILE=${HOME}/target/sgfuzz/dcmtk/enum_types.txt
    export SGFUZZ_BLOCKING_TYPE_FILE=${HOME}/profuzzbench/subjects/DICOM/dcmtk/blocking-types.txt
    opt -load-pass-plugin=${HOME}/sgfuzz-llvm-pass/sgfuzz-source-pass.so \
        -passes="sgfuzz-source" -debug-pass-manager dcmqrscp.bc -o dcmqrscp_opt.bc

    llvm-dis-17 dcmqrscp_opt.bc -o dcmqrscp_opt.ll
    sed -i 's/optnone //g' dcmqrscp_opt.ll

    clang dcmqrscp_opt.ll -o dcmqrscp \
        -lsFuzzer \
        -lhfnetdriver \
        -lhfcommon \
        -lz \
        -lm \
        -lstdc++ \
        -lpthread \
        -lrt \
        -lssl \
        -lcrypto \
        -fsanitize=address \
        -fsanitize=fuzzer \
        -DFT_FUZZING \
        -DFT_CONSUMER \
        -DSGFUZZ \
        ../lib/libdcmqrdb.a \
        ../lib/libdcmnet.a \
        ../lib/libdcmdata.a \
        ../lib/liboflog.a \
        ../lib/libofstd.a \
        ../lib/liboficonv.a 

    popd >/dev/null
}

function run_sgfuzz {
    replay_step=$1
    gcov_step=$2
    timeout=$3
    outdir=/tmp/fuzzing-output
    indir=${HOME}/profuzzbench/subjects/DICOM/dcmtk/in-dicom
    pushd ${HOME}/target/sgfuzz/dcmtk/build/bin >/dev/null

    mkdir -p $outdir/replayable-queue
    rm -rf $outdir/replayable-queue/*
    mkdir -p $outdir/crashes
    rm -rf $outdir/crashes/*

    if [ ! -d "${HOME}/ACME_STORE" ]; then
        mkdir ${HOME}/ACME_STORE
    fi

    export DCMDICTPATH=${HOME}/profuzzbench/subjects/DICOM/dcmtk/dicom.dic
    export ASAN_OPTIONS="abort_on_error=1:symbolize=1:detect_leaks=0:handle_abort=2:handle_segv=2:handle_sigbus=2:handle_sigill=2:detect_stack_use_after_return=1:detect_odr_violation=0:detect_container_overflow=0:poison_array_cookie=0"
    export HFND_TCP_PORT=5158
    export HFND_FORK_MODE=1
    export HFND_STATE_DUMP_FILES=${HOME}/ACME_STORE/index.dat
    export HFND_STATE_DUMP_DIR=${outdir}/crashes-dump

    mkdir -p ${HFND_STATE_DUMP_DIR}

    SGFuzz_ARGS=(
        -max_len=100000
        -close_fd_mask=3
        -shrink=1
        -reload=30
        -print_final_stats=1
        -detect_leaks=0
        -max_total_time=$timeout
        -fork=1
        -artifact_prefix="${outdir}/crashes/"
        "${outdir}/replayable-queue"
        "${indir}"
    )

    DCMTK_ARGS=(
        --single-process
        --config ${HOME}/profuzzbench/subjects/DICOM/dcmtk/dcmqrscp.cfg
        -d
    )

    ./dcmqrscp "${SGFuzz_ARGS[@]}" -- "${DCMTK_ARGS[@]}"

    cp /home/user/repo/dcmtk/dcmdata/libsrc/vrscanl.c /home/user/target/gcov/consumer/dcmtk
    cp /home/user/repo/dcmtk/dcmdata/libsrc/vrscanl.l /home/user/target/gcov/consumer/dcmtk
    cp /home/user/repo/dcmtk/dcmdata/libsrc/vrscanl.c /home/user/target/gcov/consumer/dcmtk/build/dcmdata/libsrc/CMakeFiles/dcmdata.dir
    cp /home/user/repo/dcmtk/dcmdata/libsrc/vrscanl.l /home/user/target/gcov/consumer/dcmtk/build/dcmdata/libsrc/CMakeFiles/dcmdata.dir

    function replay {
        /home/user/aflnet/afl-replay $1 DICOM 5158 1 &
        LD_PRELOAD=libgcov_preload.so:libfake_random.so \
        FAKE_RANDOM=1 \
        FAKETIME_ONLY_CMDS="dcmqrscp" \
            timeout -k 0 1s ./build/bin/dcmqrscp --single-process --config ${HOME}/profuzzbench/subjects/DICOM/dcmtk/dcmqrscp.cfg

        wait
        pkill dcmqrscp
    }

    cd ${HOME}/target/gcov/consumer/dcmtk/
    python3 ${HOME}/profuzzbench/scripts/sort_libfuzzer_findings.py ${outdir}/replayable-queue
    list_cmd="ls -1 ${outdir}/replayable-queue/id* | awk 'NR % ${replay_step} == 0' | tr '\n' ' ' | sed 's/ $//'"    
    clean_cmd="rm -f ${HOME}/ACME_STORE/*"
    compute_coverage replay "$list_cmd" ${gcov_step} ${outdir}/coverage.csv "" "$clean_cmd"

    function replay_poc {
        ${HOME}/aflnet/afl-replay $1 DICOM 5158 1 &
        err_output=$(timeout -k 0 -s SIGTERM 1s ${HOME}/target/asan/dcmtk/build/bin/dcmqrscp --single-process --config ${HOME}/profuzzbench/subjects/DICOM/dcmtk/dcmqrscp.cfg > /dev/null)
        wait

        pkill dcmqrscp

        echo "$err_output"
    }

    collect_asan_reports "/tmp/fuzzing-output/crashes" replay_poc "$clean_cmd"

    mkdir -p ${outdir}/cov_html
    gcovr -r . --html --html-details -o ${outdir}/cov_html/index.html

    popd >/dev/null
}

function build_ft_consumer {
    sudo cp ${HOME}/profuzzbench/scripts/ld.so.conf/ft-net.conf /etc/ld.so.conf.d/
    sudo ldconfig

    mkdir -p target/ft/consumer
    rm -rf target/ft/consumer/*
    cp -r repo/dcmtk target/ft/consumer/dcmtk
    pushd target/ft/consumer/dcmtk >/dev/null

    export AFL_PATH=${HOME}/fuzztruction-net/consumer/aflpp-consumer
    export AFL_LLVM_INSTRUMENT=CLASSIC
    export CC=${AFL_PATH}/afl-clang-fast
    export CXX=${AFL_PATH}/afl-clang-fast++
    export CFLAGS="-fsanitize=address -O3 -g -DFT_FUZZING -DFT_CONSUMER"
    export CXXFLAGS="-fsanitize=address -O3 -g -DFT_FUZZING -DFT_CONSUMER"
    export LDFLAGS="-fsanitize=address"

    mkdir build && cd build
    cmake .. \
      -DCMAKE_C_COMPILER="${CC}" \
      -DCMAKE_CXX_COMPILER="${CXX}" \
      -DCMAKE_C_FLAGS="${CFLAGS}" \
      -DCMAKE_CXX_FLAGS="${CXXFLAGS}" \
      -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" \
      -DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS}"

    make dcmqrscp ${MAKE_OPT}
    
    popd >/dev/null
}

function build_ft_generator {
    mkdir -p target/ft/generator
    rm -rf target/ft/generator/*
    cp -r repo/dcmtk target/ft/generator/dcmtk
    pushd target/ft/generator/dcmtk >/dev/null
    
    export FT_CALL_INJECTION=1
    export FT_HOOK_INS=call,branch,load,store,select,switch
    export CC=${HOME}/fuzztruction-net/generator/pass/fuzztruction-source-clang-fast
    export CXX=${HOME}/fuzztruction-net/generator/pass/fuzztruction-source-clang-fast++
    export CFLAGS="-O0 -g -DFT_FUZZING -DFT_GENERATOR"
    export CXXFLAGS="-O0 -g -DFT_FUZZING -DFT_GENERATOR"
    export GENERATOR_AGENT_SO_DIR="${HOME}/fuzztruction-net/target/release/"
    export LLVM_PASS_SO="${HOME}/fuzztruction-net/generator/pass/fuzztruction-source-llvm-pass.so"

    mkdir build && cd build
    cmake ..
    make dcmqrti ${MAKE_OPT}
    
    popd >/dev/null
}

function run_ft {
    replay_step=$1
    gcov_step=$2
    timeout=$3
    consumer="dcmtk"
    generator=${GENERATOR:-$consumer}
    work_dir=/tmp/fuzzing-output
    pushd ${HOME}/target/ft/ >/dev/null

    if [ ! -d "${HOME}/ACME_STORE" ]; then
        mkdir ${HOME}/ACME_STORE
    fi

    # synthesize the ft configuration yaml
    # according to the targeted fuzzer and generated
    temp_file=$(mktemp)
    sed -e "s|WORK-DIRECTORY|${work_dir}|g" -e "s|UID|$(id -u)|g" -e "s|GID|$(id -g)|g" ${HOME}/profuzzbench/ft-common.yaml >"$temp_file"
    cat "$temp_file" >ft.yaml
    printf "\n" >>ft.yaml
    rm "$temp_file"
    cat ${HOME}/profuzzbench/subjects/DICOM/${generator}/ft-source.yaml >>ft.yaml
    cat ${HOME}/profuzzbench/subjects/DICOM/${consumer}/ft-sink.yaml >>ft.yaml

    # running ft-net fuzzing
    sudo ${HOME}/fuzztruction-net/target/release/fuzztruction --purge ft.yaml fuzz --log-level debug -t ${timeout}s

    cp /home/user/repo/dcmtk/dcmdata/libsrc/vrscanl.c /home/user/target/gcov/consumer/dcmtk
    cp /home/user/repo/dcmtk/dcmdata/libsrc/vrscanl.l /home/user/target/gcov/consumer/dcmtk
    cp /home/user/repo/dcmtk/dcmdata/libsrc/vrscanl.c /home/user/target/gcov/consumer/dcmtk/build/dcmdata/libsrc/CMakeFiles/dcmdata.dir
    cp /home/user/repo/dcmtk/dcmdata/libsrc/vrscanl.l /home/user/target/gcov/consumer/dcmtk/build/dcmdata/libsrc/CMakeFiles/dcmdata.dir
    
    # collecting coverage results
    sudo ${HOME}/fuzztruction-net/target/release/fuzztruction ft.yaml gcov -t 3s
    sudo chmod -R 755 $work_dir
    sudo chown -R $(id -u):$(id -g) $work_dir
    cd ${HOME}/target/gcov/consumer/dcmtk
    mkdir -p ${work_dir}/cov_html
    gcovr -r . --html --html-details -o ${work_dir}/cov_html/index.html
    
    popd >/dev/null
}

function build_pingu_generator {
    mkdir -p target/pingu/generator
    rm -rf target/pingu/generator/*
    cp -r repo/dcmtk target/pingu/generator/dcmtk
    pushd target/pingu/generator/dcmtk >/dev/null

    source_pass_so="${HOME}/pingu/pingu-agent/pass/build/pingu-source-pass.so"
    extapi_bc="${HOME}/pingu/pingu-agent/pass/build/extapi.bc"
    if [ ! -f "${source_pass_so}" ] || [ ! -f "${extapi_bc}" ]; then
        echo "[!] Missing pingu source pass dependencies: ${source_pass_so}, ${extapi_bc}"
        return 1
    fi

    export LLVM_COMPILER=clang
    export CC=wllvm
    export CXX=wllvm++
    export CFLAGS="-O0 -g -fno-inline-functions -fno-inline -fno-discard-value-names -DFT_FUZZING -DFT_GENERATOR"
    export CXXFLAGS="-O0 -g -fno-inline-functions -fno-inline -fno-discard-value-names -DFT_FUZZING -DFT_GENERATOR"
    export LLVM_BITCODE_GENERATION_FLAGS=""

    mkdir build && cd build
    cmake ..
    rm -f compile_commands.json
    bear --output compile_commands.json -- make dcmqrti ${MAKE_OPT}

    cd bin
    extract-bc dcmqrti

    opt -load-pass-plugin="${source_pass_so}" \
        -passes="pingu-source" -debug-pass-manager \
        -ins=load,store,call,memcpy,trampoline,ret,icmp,memcmp -role=source -svf=1 -dump-svf=0 \
        -extapi-path="${extapi_bc}" \
        dcmqrti.bc -o dcmqrti_opt.bc

    llvm-dis dcmqrti_opt.bc -o dcmqrti_opt.ll
    sed -i 's/optnone //g' dcmqrti_opt.ll

    clang -O0 -L"${HOME}/pingu/target/release" -Wl,-rpath,"${HOME}/pingu/target/release" \
        -lpingu_agent -fsanitize=address \
        dcmqrti_opt.ll -o dcmqrti \
        -lz -lm -lstdc++ -lpthread -lrt -lssl -lcrypto \
        ../lib/libdcmqrdb.a \
        ../lib/libdcmnet.a \
        ../lib/libdcmdata.a \
        ../lib/liboflog.a \
        ../lib/libofstd.a \
        ../lib/liboficonv.a

    popd >/dev/null
}

function build_pingu_consumer {
    sudo cp ${HOME}/profuzzbench/scripts/ld.so.conf/pingu.conf /etc/ld.so.conf.d/
    sudo ldconfig

    mkdir -p target/pingu/consumer
    rm -rf target/pingu/consumer/*
    cp -r repo/dcmtk target/pingu/consumer/dcmtk
    pushd target/pingu/consumer/dcmtk >/dev/null

    source_pass_so="${HOME}/pingu/pingu-agent/pass/build/pingu-source-pass.so"
    afl_pass_so="${HOME}/pingu/pingu-agent/pass/build/afl-llvm-pass.so"
    extapi_bc="${HOME}/pingu/pingu-agent/pass/build/extapi.bc"
    if [ ! -f "${source_pass_so}" ] || [ ! -f "${afl_pass_so}" ] || [ ! -f "${extapi_bc}" ]; then
        echo "[!] Missing pingu consumer pass dependencies: ${source_pass_so}, ${afl_pass_so}, ${extapi_bc}"
        return 1
    fi

    export LLVM_COMPILER=clang
    export CC=wllvm
    export CXX=wllvm++
    export CFLAGS="-O0 -g -fno-inline-functions -fno-inline -fno-discard-value-names -DFT_FUZZING -DFT_CONSUMER"
    export CXXFLAGS="-O0 -g -fno-inline-functions -fno-inline -fno-discard-value-names -DFT_FUZZING -DFT_CONSUMER"
    export LLVM_BITCODE_GENERATION_FLAGS=""

    mkdir build && cd build
    cmake ..
    rm -f compile_commands.json
    bear --output compile_commands.json -- make dcmqrscp ${MAKE_OPT}

    cd bin
    extract-bc dcmqrscp

    opt -load-pass-plugin="${source_pass_so}" \
        -load-pass-plugin="${afl_pass_so}" \
        -passes="pingu-source,afl-coverage" -debug-pass-manager \
        -ins=load,store,call,memcpy,icmp,memcmp,ret -role=sink -svf=1 -dump-svf=0 \
        -extapi-path="${extapi_bc}" \
        dcmqrscp.bc -o dcmqrscp_opt.bc

    llvm-dis dcmqrscp_opt.bc -o dcmqrscp_opt.ll
    sed -i 's/optnone //g' dcmqrscp_opt.ll

    clang -O0 -L"${HOME}/pingu/target/release" -Wl,-rpath,"${HOME}/pingu/target/release" \
        -lpingu_agent -fsanitize=address \
        dcmqrscp_opt.ll -o dcmqrscp \
        -lz -lm -lstdc++ -lpthread -lrt -lssl -lcrypto \
        ../lib/libdcmqrdb.a \
        ../lib/libdcmnet.a \
        ../lib/libdcmdata.a \
        ../lib/liboflog.a \
        ../lib/libofstd.a \
        ../lib/liboficonv.a

    popd >/dev/null
}

function run_pingu {
    local timeout
    consumer="dcmtk"
    local replay_step="${1:-1}"
    local gcov_step="${2:-1}"
    if [[ "${replay_step}" =~ ^[0-9]+$ ]] && [[ "${gcov_step}" =~ ^[0-9]+$ ]] && [[ "${3:-}" =~ ^[0-9]+$ ]]; then
        # New dispatcher order: replay_step gcov_step timeout [generator]
        timeout=$3
        generator=${4-$consumer}
    else
        # Legacy order: timeout [generator]
        timeout=${1:-600}
        generator=${2-$consumer}
    fi
    work_dir=/tmp/fuzzing-output
    pingu_bin=${HOME}/pingu/target/release/pingu
    if [ ! -x "${pingu_bin}" ]; then
        pingu_bin=${HOME}/pingu/target/debug/pingu
    fi
    if [ ! -x "${pingu_bin}" ]; then
        echo "[!] Missing pingu binary: ${HOME}/pingu/target/release/pingu or ${HOME}/pingu/target/debug/pingu"
        return 1
    fi
    pushd ${HOME}/target/pingu/ >/dev/null

    # synthesize the pingu configuration yaml according to source and sink
    temp_file=$(mktemp)
    pingu_common_cfg=${HOME}/profuzzbench/pingu-common.yaml
    if [ ! -f "${pingu_common_cfg}" ]; then
        pingu_common_cfg=${HOME}/profuzzbench/pingu.yaml
    fi
    sed -e "s|WORK-DIRECTORY|${work_dir}|g" \
        -e "s|UID|$(id -u)|g" \
        -e "s|GID|$(id -g)|g" \
        -e "s|TIMEOUT|${timeout}s|g" \
        -e "s|target:[[:space:]]*wolfssl|target: dcmtk|g" \
        -e 's|sut:[[:space:]]*"wolfssl"|sut: "dcmtk"|g' \
        -e 's|protocol:[[:space:]]*"tls"|protocol: "dicom"|g' \
        "${pingu_common_cfg}" >"${temp_file}"
    cat "${temp_file}" >pingu.yaml
    printf "\n" >>pingu.yaml
    rm "${temp_file}"

    generator_source_cfg=${HOME}/profuzzbench/subjects/DICOM/${generator}/pingu-source.yaml
    consumer_sink_cfg=${HOME}/profuzzbench/subjects/DICOM/${consumer}/pingu-sink.yaml
    if [ -f "${generator_source_cfg}" ]; then
        cat "${generator_source_cfg}" >>pingu.yaml
    else
        sed 's|/target/ft/|/target/pingu/|g' "${HOME}/profuzzbench/subjects/DICOM/${generator}/ft-source.yaml" >>pingu.yaml
    fi
    printf "\n" >>pingu.yaml
    if [ -f "${consumer_sink_cfg}" ]; then
        cat "${consumer_sink_cfg}" >>pingu.yaml
    else
        sed 's|/target/ft/|/target/pingu/|g' "${HOME}/profuzzbench/subjects/DICOM/${consumer}/ft-sink.yaml" >>pingu.yaml
    fi

    # running pingu (campaign duration is controlled externally)
    sudo timeout "${timeout}s" "${pingu_bin}" pingu.yaml -vvv --purge fuzz || true

    cp /home/user/repo/dcmtk/dcmdata/libsrc/vrscanl.c /home/user/target/gcov/consumer/dcmtk
    cp /home/user/repo/dcmtk/dcmdata/libsrc/vrscanl.l /home/user/target/gcov/consumer/dcmtk
    cp /home/user/repo/dcmtk/dcmdata/libsrc/vrscanl.c /home/user/target/gcov/consumer/dcmtk/build/dcmdata/libsrc/CMakeFiles/dcmdata.dir
    cp /home/user/repo/dcmtk/dcmdata/libsrc/vrscanl.l /home/user/target/gcov/consumer/dcmtk/build/dcmdata/libsrc/CMakeFiles/dcmdata.dir

    # replay_step / gcov_step are accepted for dispatcher compatibility.
    sudo "${pingu_bin}" pingu.yaml -vvv gcov --pcap --purge
    sudo chmod -R 755 "${work_dir}"
    sudo chown -R $(id -u):$(id -g) "${work_dir}"
    cd ${HOME}/target/gcov/consumer/dcmtk
    mkdir -p ${work_dir}/cov_html
    gcovr -r . --html --html-details -o ${work_dir}/cov_html/index.html

    popd >/dev/null
}

function build_gcov {
    mkdir -p target/gcov/consumer
    rm -rf target/gcov/consumer/*
    cp -r repo/dcmtk target/gcov/consumer/dcmtk
    pushd target/gcov/consumer/dcmtk >/dev/null

    export CFLAGS="-O0 -g -fprofile-arcs -ftest-coverage"
    export CXXFLAGS="-O0 -g -fprofile-arcs -ftest-coverage"
    export LDFLAGS="-g -fprofile-arcs -ftest-coverage"
   
    mkdir build && cd build
    cmake ..
    make dcmqrscp ${MAKE_OPT}

    rm -rf fuzz test .git doc

    popd >/dev/null
}

function build_asan {
    if [ ! -d ".git-cache/dcmtk" ]; then
        git clone --no-single-branch https://github.com/dcmtk/dcmtk.git .git-cache/dcmtk
    fi

    mkdir -p repo
    cp -r .git-cache/dcmtk repo/dcmtk-raw

    pushd repo/dcmtk >/dev/null

    git fetch --unshallow
    git rebase "$1"
    
    popd >/dev/null

    mkdir -p target/asan
    rm -rf target/asan/*
    cp -r repo/dcmtk-raw target/asan/dcmtk
    pushd target/asan/dcmtk >/dev/null

    export CC=clang
    export CXX=clang++
    export CFLAGS="-O0 -g -fsanitize=address"
    export CXXFLAGS="-O0 -g -fsanitize=address"
    export LDFLAGS="-fsanitize=address"

    mkdir build && cd build
    cmake ..
    make dcmqrscp ${MAKE_OPT}

    popd >/dev/null
}

function install_dependencies {
    echo "No dependencies"
}
