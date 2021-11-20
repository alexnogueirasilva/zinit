#!/usr/bin/env bash

parent_process() {
  local ppid pcmd
  ppid="$(ps -o ppid= -p "$$" | awk '{ print $1 }')"

  if [[ -z "$ppid" ]]
  then
    echo "Failed to determine parent process" >&2
    return 1
  fi

  if pcmd="$(ps -o cmd= -p "$ppid")"
  then
    echo "$pcmd"
    return
  fi

  return 1
}

running_interactively() {
  if [[ -n "$CI" ]]
  then
    return 1
  fi

  if ! [[ -t 1 ]]
  then
    # return false if running non-interactively, unless run with zunit
    parent_process | grep -q zunit
  fi
}

create_init_config_file() {
  local tempfile

  if [[ -z "$*" ]]
  then
    return 1
  fi

  tempfile="$(mktemp)"
  echo "$*" > "$tempfile"
  echo "$tempfile"
}

run() {
  local image="${CONTAINER_IMAGE:-ghcr.io/zdharma-continuum/zinit}"
  local tag="${CONTAINER_TAG:-latest}"
  local init_config="$1"
  shift

  local -a args=(--rm)

  if running_interactively
  then
    args+=(--tty=true --interactive=true)
  fi

  if [[ -n "$init_config" ]]
  then
    if [[ -r "$init_config" ]]
    then
      args+=(--volume "${init_config}:/init.zsh")
    else
      echo "❌ Init config file is not readable" >&2
      return 1
    fi
  fi

  if [[ -n "${CONTAINER_VOLUMES[*]}" ]]
  then
    local vol
    for vol in "${CONTAINER_VOLUMES[@]}"
    do
      args+=(--volume "${vol}")
    done
  fi

  local -a cmd=("$@")

  if [[ -n "$WRAP_CMD" ]]
  then
    cmd=(zsh -silc "${cmd[*]}")
  fi

  if [[ -n "$DEBUG" ]]
  then
    {
      # The @Q below is necessary to keep the quotes intact
      # https://stackoverflow.com/a/12985353/1872036
      echo -e "🚀 \e[35mRunning command"
      echo -e "\$ docker ${args[*]} run $image:$tag ${cmd[*]@Q}\e[0m"
    } >&2
  fi

  docker run "${args[@]}" "$image:$tag" "${cmd[@]}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  CONTAINER_IMAGE=${CONTAINER_IMAGE:-ghcr.io/zdharma-continuum/zinit}
  CONTAINER_TAG="${CONTAINER_TAG:-latest}"
  CONTAINER_VOLUMES=()
  DEBUG="${DEBUG:-}"
  INIT_CONFIG_VAL="${INIT_CONFIG_VAL:-}"
  WRAP_CMD="${WRAP_CMD:-}"

  while [[ -n "$*" ]]
  do
    case "$1" in
      # Fetch init config from clipboard (Linux only)
      --xsel|-b)
        INIT_CONFIG_VAL="$(xsel -b)"
        shift
        ;;
      -c|--config|--init-config|--init)
        INIT_CONFIG_VAL="$2"
        shift 2
        ;;
      -d|--debug)
        DEBUG=1
        shift
        ;;
      -i|--image)
        CONTAINER_IMAGE="$2"
        shift 2
        ;;
      -t|--tag)
        CONTAINER_TAG="$2"
        shift 2
        ;;
      # Additional container volumes
      -v|--volume)
        CONTAINER_VOLUMES+=("$2")
        shift 2
        ;;
      # Whether to wrap the command in zsh -silc
      -w|--wrap)
        WRAP_CMD=1
        shift
        ;;
      --tests|--zunit)
        ZUNIT=1
        shift
        ;;
      *)
        break
        ;;
    esac
  done

  if INIT_CONFIG="$(create_init_config_file "$INIT_CONFIG_VAL")"
  then
    trap 'rm -vf $INIT_CONFIG' EXIT INT
  fi

  if [[ -n "$ZUNIT" ]]
  then
    ROOT_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1; pwd -P)" || exit 9
    # Mount root of the repo to /src
    # Mount /tmp/zunit-zinit to /data
    CONTAINER_VOLUMES+=(
      "${ROOT_DIR}:/src"
      "${TMPDIR:-/tmp}/zunit-zinit:/data"
      # TODO DIRTYFIX TO BE REMOVED BEFORE MERGING
      "${ROOT_DIR}/docker/zshenv:/home/user01/.zshenv"
      "${ROOT_DIR}/docker/zshrc:/home/user01/.zshrc"
    )
  fi

  run "$INIT_CONFIG" "$@"
fi