#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DEFAULT_BUILD_ROOT="$(cd "${SOURCE_DIR}/.." && pwd)/101_FreeCAD_Build"
BUILD_ROOT="${DEFAULT_BUILD_ROOT}"
BUILD_DIR=""
BUILD_TYPE="Debug"
DO_FRESH="false"
COMMAND="all"
JOBS=""
declare -a EXTRA_ARGS=()
declare -a BUILD_TARGETS=()

detect_cpu_count() {
    if command -v getconf >/dev/null 2>&1; then
        getconf _NPROCESSORS_ONLN
        return
    fi
    if command -v nproc >/dev/null 2>&1; then
        nproc
        return
    fi
    echo 2
}

default_jobs() {
    local cpu_count
    cpu_count="$(detect_cpu_count)"
    if [[ "${cpu_count}" =~ ^[0-9]+$ ]] && (( cpu_count > 1 )); then
        local limit=$(((cpu_count - 1) / 2))
        (( limit < 1 )) && limit=1
        echo "${limit}"
    else
        echo 1
    fi
}

usage() {
    cat <<EOF
Usage:
  $(basename "$0") [all|configure|build|run-cmd|run-gui] [options] [-- <extra args>]

Defaults:
  source dir:      ${SOURCE_DIR}
  build root:      ${DEFAULT_BUILD_ROOT}
    build dir:       <build-root>/<build-type-lowercase>
  command:         all (configure + build)
  jobs:            auto (at most half-minus-one CPUs, so >50% stays free)

Options:
  --build-root <path>   External build root (default: ${DEFAULT_BUILD_ROOT})
  --build-type <type>   CMAKE_BUILD_TYPE (default: Debug)
  --jobs <n>            Parallel jobs for build
  --fresh               Use CMake --fresh during configure
  --target <name>       Add a build target (repeatable)
  -h, --help            Show this help

Examples:
  $(basename "$0")
  $(basename "$0") configure --fresh
  $(basename "$0") build --jobs 4 --target FreeCADMain --target FreeCADMainCmd
  $(basename "$0") run-cmd -- --version
  $(basename "$0") run-gui
EOF
}

while (($#)); do
    case "$1" in
        all|configure|build|run-cmd|run-gui)
            COMMAND="$1"
            shift
            ;;
        --build-root)
            BUILD_ROOT="$2"
            shift 2
            ;;
        --build-type)
            BUILD_TYPE="$2"
            shift 2
            ;;
        --jobs)
            JOBS="$2"
            shift 2
            ;;
        --fresh)
            DO_FRESH="true"
            shift
            ;;
        --target)
            BUILD_TARGETS+=("$2")
            shift 2
            ;;
        --)
            shift
            EXTRA_ARGS=("$@")
            break
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

BUILD_TYPE_LOWER="$(printf '%s' "${BUILD_TYPE}" | tr '[:upper:]' '[:lower:]')"
BUILD_DIR="${BUILD_ROOT}/${BUILD_TYPE_LOWER}"
JOBS="${JOBS:-$(default_jobs)}"

if ! [[ "${JOBS}" =~ ^[0-9]+$ ]] || (( JOBS < 1 )); then
    echo "Invalid --jobs value: ${JOBS}" >&2
    exit 1
fi

run_configure() {
    mkdir -p "${BUILD_DIR}"
    local -a cmake_args=(
        -S "${SOURCE_DIR}"
        -B "${BUILD_DIR}"
        -DCMAKE_BUILD_TYPE="${BUILD_TYPE}"
        -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
        -DCMAKE_JOB_POOL_COMPILE=compile_jobs
        -DCMAKE_JOB_POOL_LINK=link_jobs
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    )
    if [[ "${DO_FRESH}" == "true" ]]; then
        cmake_args+=(--fresh)
    fi
    echo "[configure] cmake ${cmake_args[*]}"
    cmake "${cmake_args[@]}"
}

run_build() {
    local -a build_args=(
        --build "${BUILD_DIR}"
        --parallel "${JOBS}"
    )
    if ((${#BUILD_TARGETS[@]})); then
        build_args+=(--target "${BUILD_TARGETS[@]}")
    fi
    echo "[build] cmake ${build_args[*]}"
    cmake "${build_args[@]}"
}

run_cmd() {
    local bin="${BUILD_DIR}/bin/FreeCADCmd"
    if [[ ! -x "${bin}" ]]; then
        echo "Missing binary: ${bin}" >&2
        echo "Run: $(basename "$0") all" >&2
        exit 1
    fi
    echo "[run-cmd] ${bin} ${EXTRA_ARGS[*]-}"
    "${bin}" "${EXTRA_ARGS[@]}"
}

run_gui() {
    local bin="${BUILD_DIR}/bin/FreeCAD"
    if [[ ! -x "${bin}" ]]; then
        echo "Missing binary: ${bin}" >&2
        echo "Run: $(basename "$0") all" >&2
        exit 1
    fi
    echo "[run-gui] ${bin} ${EXTRA_ARGS[*]-}"
    "${bin}" "${EXTRA_ARGS[@]}"
}

case "${COMMAND}" in
    all)
        run_configure
        run_build
        ;;
    configure)
        run_configure
        ;;
    build)
        run_build
        ;;
    run-cmd)
        run_cmd
        ;;
    run-gui)
        run_gui
        ;;
esac
