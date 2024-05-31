# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/)
# Copyright 2024-present Datadog, Inc.

# This script installs Datadog tracing libraries for the specified languages
# and prints to standard output the environment variables that need to be set for enabling Test Visibility.

# The variables are printed in the following format: variableName=variableValue

ARTIFACTS_FOLDER="${DD_TRACER_FOLDER:-$(pwd)/.datadog}"
if ! mkdir -p $ARTIFACTS_FOLDER; then
  >&2 echo "Error: Cannot create folder: $ARTIFACTS_FOLDER"
  return 1
fi

install_java_tracer() {
  local url="https://dtdg.co/latest-java-tracer"
  local filepath="$ARTIFACTS_FOLDER/dd-java-agent.jar"

  if command -v curl >/dev/null 2>&1; then
    curl -Lo "$filepath" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$filepath" "$url"
  else
    >&2 echo "Error: Neither wget nor curl is installed."
    return 1
  fi

  local updated_java_tool_options="-javaagent:$filepath $JAVA_TOOL_OPTIONS"
  if [ ${#updated_java_tool_options} -le 1024 ]; then
    echo "JAVA_TOOL_OPTIONS=$updated_java_tool_options"
  else
    >&2 echo "Error: Cannot apply Java instrumentation: updated JAVA_TOOL_OPTIONS would exceed 1024 characters"
    return 1
  fi
}

install_js_tracer() {
  if ! command -v npm >/dev/null 2>&1; then
    >&2 echo "Error: npm is not installed."
    return 1
  fi

  if ! command -v node >/dev/null 2>&1; then
    >&2 echo "Error: node is not installed."
    return 1
  fi

  if ! is_node_version_compliant; then
    >&2 echo "Error: node v18.0.0 or newer is required, got $(node -v)"
    return 1
  fi

  # set location for installing global packages (the script may not have the permissions to write to the default one)
  export NPM_CONFIG_PREFIX=$ARTIFACTS_FOLDER

  # install dd-trace as a "global" package
  # (otherwise, doing SCM checkout might rollback the changes to package.json, and any subsequent `npm install` calls will result in removing the package)
  if ! npm install -g dd-trace >&2; then
    >&2 echo "Error: Could not install dd-trace for JS"
    return 1
  fi

  # Github Actions prohibit setting NODE_OPTIONS
  local dd_trace_path="$ARTIFACTS_FOLDER/lib/node_modules/dd-trace/ci/init"
  if ! is_github_actions; then
    echo "NODE_OPTIONS=$NODE_OPTIONS -r $dd_trace_path"
  else
    echo "DD_TRACE_PACKAGE=$dd_trace_path"
  fi
}

is_node_version_compliant() {
  local node_version=$(node -v | cut -d 'v' -f 2)
  local major_node_version=$(echo $node_version | cut -d '.' -f 1)
  if [ "$major_node_version" -lt 18 ]; then
    return 1
  fi
}

is_github_actions() {
  if [ -z "$GITHUB_ACTION" ]; then
    return 1
  fi
}

install_python_tracer() {
  if ! command -v pip >/dev/null 2>&1; then
    >&2 echo "Error: pip is not installed."
    return 1
  fi

  python -m venv .dd_civis_env >&2
  source .dd_civis_env/bin/activate >&2

  if ! pip install -U ddtrace coverage >&2; then
    >&2 echo "Error: Could not install ddtrace for Python"
    return 1
  fi

  local dd_trace_path=$(pip show ddtrace | grep Location | awk '{print $2}')
  if ! [ -d $dd_trace_path ]; then
    >&2 echo "Error: Could not determine ddtrace package location (tried $dd_trace_path)"
    return 1
  fi

  local coverage_path=$(pip show coverage | grep Location | awk '{print $2}')
  if ! [ -d $coverage_path ]; then
    >&2 echo "Error: Could not determine coverage package location (tried $coverage_path)"
    return 1
  fi

  echo "PYTHONPATH=$dd_trace_path:$coverage_path:$PYTHONPATH"
  echo "PYTEST_ADDOPTS=--ddtrace $PYTEST_ADDOPTS"

  deactivate >&2
}

install_dotnet_tracer() {
  if ! command -v dotnet >/dev/null 2>&1; then
    >&2 echo "Error: dotnet is not installed."
    return 1
  fi

  if ! dotnet tool update --tool-path $ARTIFACTS_FOLDER dd-trace >&2; then
    >&2 echo "Error: Could not install dd-trace for .NET"
    return 1
  fi

  if [ -z "$DD_API_KEY" ]; then
    >&2 echo "Error: dd-trace for .NET configuration requires DD_API_KEY to be set"
    return 1
  fi

  # Using "jenkins" for now, as it outputs the env vars in a provider-agnostic format.
  # Grepping to filter out lines that are not environment variables
  DD_CIVISIBILITY_AGENTLESS_ENABLED=true $ARTIFACTS_FOLDER/dd-trace ci configure jenkins | grep '='
}

# set common environment variables
echo "DD_CIVISIBILITY_ENABLED=true"
echo "DD_CIVISIBILITY_AGENTLESS_ENABLED=true"

if [ -z "$DD_ENV" ]; then
  echo "DD_ENV=ci"
fi

# install tracer libraries
if [ -n "$DD_CIVISIBILITY_INSTRUMENTATION_LANGUAGES" ]; then
  if [ "$DD_CIVISIBILITY_INSTRUMENTATION_LANGUAGES" = "all" ]; then
    DD_CIVISIBILITY_INSTRUMENTATION_LANGUAGES="java js python dotnet"
  fi

  for lang in $( echo "$DD_CIVISIBILITY_INSTRUMENTATION_LANGUAGES" )
  do
    case $lang in
      java)
        install_java_tracer
        ;;
      js)
        install_js_tracer
        ;;
      python)
        install_python_tracer
        ;;
      dotnet)
        install_dotnet_tracer
        ;;
      *)
        >&2 echo "Unknown language: $lang. Must be one of: java, js, python, dotnet"
        exit 1;
        ;;
    esac
  done
else
  >&2 echo "Error: DD_CIVISIBILITY_INSTRUMENTATION_LANGUAGES environment variable should be set to all or a space-separated subset of java, js, python, dotnet"
  exit 1;
fi
