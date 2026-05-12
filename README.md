# <img height="25" src="logos/test_visibility_logo.png" /> Datadog Test Optimization GitHub Action

GitHub Action that installs and configures [Datadog Test Optimization](https://docs.datadoghq.com/tests/).
Supported languages are .NET, Java, Javascript, Python, Ruby and Go.

## About Datadog Test Optimization

[Test Optimization](https://docs.datadoghq.com/tests/) provides a test-first view into your CI health by displaying important metrics and results from your tests.
It can help you investigate and mitigate performance problems and test failures that are most relevant to your work, focusing on the code you are responsible for, rather than the pipelines which run your tests.

## Usage

1. Set [Datadog API key](https://app.datadoghq.com/organization-settings/api-keys) inside Settings > Secrets as `DD_API_KEY`.
2. Add a step to your GitHub Actions workflow YAML that uses this action. Set the language and [site](https://docs.datadoghq.com/getting_started/site/) parameters:

   ```yaml
   steps:
     - name: Configure Datadog Test Optimization
       uses: datadog/test-visibility-github-action@v2
       with:
         languages: java
         api_key: ${{ secrets.DD_API_KEY }}
         site: datadoghq.com # Change if your site is not US1
     - name: Run unit tests
       run: |
         mvn clean test
   ```

> [!IMPORTANT]
> It is best if the new step comes **right before** the step that runs your tests.
> Otherwise, installed tracing libraries might be removed by the steps that precede tests execution
> (for example, `actions/checkout` will wipe out whatever was installed in the action workspace).

## Configuration

The action has the following parameters:

| Name                           | Description                                                                                                                                                                                                                                                                                         | Required | Default       |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ------------- |
| languages                      | List of languages to be instrumented. Can be either "all" or any of "java", "js", "python", "dotnet", "ruby", "go" (multiple languages can be specified as a space-separated list).                                                                                                                 | true     |               |
| api_key                        | Datadog API key. Can be found at <https://app.datadoghq.com/organization-settings/api-keys>                                                                                                                                                                                                           | true     |               |
| site                           | Datadog site. See <https://docs.datadoghq.com/getting_started/site> for more information about sites.                                                                                                                                                                                                 | false    | datadoghq.com |
| service                        | The name of the service or library being tested.                                                                                                                                                                                                                                                    | false    |               |
| dotnet-tracer-version          | The version of Datadog .NET tracer to use. Defaults to the latest release.                                                                                                                                                                                                                          | false    |               |
| java-tracer-version            | The version of Datadog Java tracer to use. Defaults to the latest release.                                                                                                                                                                                                                          | false    |               |
| js-tracer-version              | The version of Datadog JS tracer to use. Defaults to the latest release.                                                                                                                                                                                                                            | false    |               |
| python-tracer-version          | The version of Datadog Python tracer to use. Defaults to the latest release.                                                                                                                                                                                                                        | false    |               |
| python-coverage-version        | The version of the Python `coverage` package to use. Defaults to `7.13.5`.                                                                                                                                                                                                                          | false    |               |
| ruby-tracer-version            | The version of datadog-ci Ruby gem to use. Defaults to the latest release.                                                                                                                                                                                                                          | false    |               |
| go-tracer-version              | The version of Orchestrion to use. Defaults to the latest release.                                                                                                                                                                                                                                  | false    |               |
| go-module-dir                  | Path to the Go module root directory to instrument. Use this when the repository contains multiple Go modules or the Go module is not in the workspace root.                                                                                                                                       | false    |               |
| java-instrumented-build-system | If provided, only the specified build systems will be instrumented (allowed values are `gradle`,`maven`,`sbt`,`ant`,`all`). `all` is a special value that instruments every Java process. If this property is not provided, all known build systems will be instrumented (Gradle, Maven, SBT, Ant). | false    |               |
| java-tracer-repository-url     | Base URL of a Maven repository (or proxy/mirror) used to download the Java tracer JAR and its sha256. The path under the base must follow the standard Maven layout for `com.datadoghq:dd-java-agent`. Defaults to Maven Central.                                            | false    |               |
| java-tracer-repository-auth-header | Optional HTTP header used to authenticate against `java-tracer-repository-url`, provided as a complete `Name: Value` string (e.g. `Authorization: Bearer <token>`). Only used when `java-tracer-repository-url` is set. Redirects are not followed when this option is set.                                                                         | false    |               |
| cache                          | Enable caching of downloaded tracers.                                                                                                                                                                                                                                                               | false    | true          |
| print-github-step-summary      | Print a summary of the installed tracers to the GitHub step summary. If set to false, the summary is printed to console instead.                                                                                                                                                                    | false    | true          |

### Additional configuration

Any [additional configuration values](https://docs.datadoghq.com/tracing/trace_collection/library_config/) can be added directly to the step that runs your tests:

```yaml
- name: Run unit tests
  run: |
    mvn clean test
  env:
    DD_ENV: staging-tests
    DD_TAGS: layer:api,team:intake,key:value
```

### Using a Maven mirror or proxy for the Java tracer

By default the Java tracer JAR is fetched from Maven Central (`https://repo1.maven.org/maven2`). Organizations with their own mirror or proxy (such as JFrog Artifactory) can point the action at it to avoid Maven Central rate limits:

```yaml
- name: Configure Datadog Test Optimization
  uses: datadog/test-visibility-github-action@v2
  with:
    languages: java
    api_key: ${{ secrets.DD_API_KEY }}
    java-tracer-repository-url: https://artifactory.example.com/maven-virtual/com/datadoghq/dd-java-agent
    java-tracer-repository-auth-header: Authorization: Bearer ${{ secrets.ARTIFACTORY_TOKEN }}
```

The base URL must expose the standard Maven layout for `com.datadoghq:dd-java-agent` (i.e. `<base>/<version>/dd-java-agent-<version>.jar` and the matching `.sha256`, plus `<base>/maven-metadata.xml` when no `java-tracer-version` is pinned). The `.sha256` files are still verified.

### Go multi-module repositories

If your repository contains multiple Go modules, or the Go module you want to instrument is not at the workspace root, set `go-module-dir` to the module root directory that contains the target `go.mod` file:

```yaml
- name: Configure Datadog Test Optimization
  uses: datadog/test-visibility-github-action@v2
  with:
    languages: go
    api_key: ${{ secrets.DD_API_KEY }}
    go-module-dir: ./services/payments
```

## Limitations

For security reasons Github [does not allow](https://github.blog/changelog/2023-10-05-github-actions-node_options-is-now-restricted-from-github_env/) actions to alter the `NODE_OPTIONS` environment variable, so you'll have to pass it manually.

### Tracing JS tests (except `vitest` and `cypress`)

If you're running tests with [vitest](https://github.com/vitest-dev/vitest), go to [Tracing vitest tests](#tracing-vitest-tests).

To work around the `NODE_OPTIONS` limitation, the action provides a separate `DD_TRACE_PACKAGE` variable that needs to be appended to `NODE_OPTIONS` manually:

```yaml
- name: Run tests
  shell: bash
  run: npm run test-ci
  env:
    NODE_OPTIONS: -r ${{ env.DD_TRACE_PACKAGE }}
```

**NOTE**: To instrument your [Cypress](https://www.cypress.io/) tests with Datadog Test Optimization, please follow the manual steps in the [docs](https://docs.datadoghq.com/tests/setup/javascript/?tab=cypress).

### Tracing vitest tests

ℹ️ This section is only relevant if you're running tests with [vitest](https://github.com/vitest-dev/vitest).

To work around the `NODE_OPTIONS` limitation, the action provides a separate `DD_TRACE_PACKAGE` and `DD_TRACE_ESM_IMPORT` variables that need to be appended to `NODE_OPTIONS` manually:

```yaml
- name: Run tests
  shell: bash
  run: npm run test:vitest
  env:
    NODE_OPTIONS: -r ${{ env.DD_TRACE_PACKAGE }} --import ${{ env.DD_TRACE_ESM_IMPORT }}
```

**Important**: `vitest` and `dd-trace` require Node.js>=18.19 or Node.js>=20.6 to work together.
