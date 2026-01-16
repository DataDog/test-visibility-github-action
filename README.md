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
| api_key                        | Datadog API key. Can be found at https://app.datadoghq.com/organization-settings/api-keys                                                                                                                                                                                                           | true     |               |
| site                           | Datadog site. See https://docs.datadoghq.com/getting_started/site for more information about sites.                                                                                                                                                                                                 | false    | datadoghq.com |
| service                        | The name of the service or library being tested.                                                                                                                                                                                                                                                    | false    |               |
| dotnet-tracer-version          | The version of Datadog .NET tracer to use. Defaults to the latest release.                                                                                                                                                                                                                          | false    |               |
| java-tracer-version            | The version of Datadog Java tracer to use. Defaults to the latest release.                                                                                                                                                                                                                          | false    |               |
| js-tracer-version              | The version of Datadog JS tracer to use. Defaults to the latest release.                                                                                                                                                                                                                            | false    |               |
| python-tracer-version          | The version of Datadog Python tracer to use. Defaults to the latest release.                                                                                                                                                                                                                        | false    |               |
| ruby-tracer-version            | The version of datadog-ci Ruby gem to use. Defaults to the latest release.                                                                                                                                                                                                                          | false    |               |
| go-tracer-version              | The version of Orchestrion to use. Defaults to the latest release.                                                                                                                                                                                                                                  | false    |               |
| java-instrumented-build-system | If provided, only the specified build systems will be instrumented (allowed values are `gradle`,`maven`,`sbt`,`ant`,`all`). `all` is a special value that instruments every Java process. If this property is not provided, all known build systems will be instrumented (Gradle, Maven, SBT, Ant). | false    |               |
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
