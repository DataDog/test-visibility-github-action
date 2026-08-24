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
       uses: datadog/test-visibility-github-action@v3
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

### Choose an action version

Starting with v3, each action release pins its default library versions instead of resolving `latest` at runtime. The action reference after `@` determines whether your workflow receives newer action releases and their pinned library versions:

| Reference | Example | Advantages | Disadvantages |
| --------- | ------- | ---------- | ------------- |
| Moving major | `datadog/test-visibility-github-action@v3` | Automatically receives reviewed bug fixes and library bumps released within v3. It will not move to v4. | The action code and default library versions can change between workflow runs. |
| Exact release tag | `datadog/test-visibility-github-action@v3.0.0` | Uses a readable, known action release and its pinned library versions. Release notes make changes easy to review before upgrading. | Does not receive bug fixes or library bumps automatically. Tags can technically be moved, so this is not as strong an immutability guarantee as a full commit SHA. |
| Full commit SHA | `datadog/test-visibility-github-action@<full-commit-sha> # v3.0.0` | Strongest reproducibility and supply-chain protection: every run uses the exact same action code and pinned library versions. | Does not receive fixes or new releases automatically. Replace the placeholder with the full SHA for the release you reviewed and use an update mechanism such as Dependabot. |

These references select the action code and its default library snapshot. To keep an individual library on a specific version independently of the action reference, [set its version input explicitly](#pin-an-individual-library-version).

For most workflows, `@v3` provides the simplest way to receive compatible updates. For workflows that require an immutable action, use the full commit SHA associated with a v3 release. Keeping the release tag as an inline comment lets readers identify the version and allows Dependabot to update the comment with the SHA.

To have Dependabot propose updates for an action pinned to a SHA, add the following to `.github/dependabot.yml` in the repository that uses the action:

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
```

Dependabot then opens pull requests when newer action releases are available, so the new SHA and any changes to the pinned library versions can be reviewed before merging. See GitHub's guidance on [keeping actions up to date with Dependabot](https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/secure-your-dependencies/auto-update-actions) and [pinning actions securely](https://docs.github.com/en/actions/reference/security/secure-use#using-third-party-actions).

### Migrate from v2 to v3

The `v2` reference does not move to v3 automatically. Update the action reference in each workflow you want to migrate:

```diff
- uses: datadog/test-visibility-github-action@v2
+ uses: datadog/test-visibility-github-action@v3
```

No input names or required configuration change. The migration only changes how omitted library-version inputs are resolved:

| Your workflow | Experience after migrating |
| ------------- | -------------------------- |
| No library-version inputs | The first v3 run uses the versions listed in the [configuration table](#configuration), which may differ from the versions resolved by the last v2 run. Defaults no longer change independently on every run. |
| Explicit library-version inputs | Your selected versions continue to override the action defaults, so the installed library versions do not change as part of the migration. |

With `@v3`, pinned defaults change only when a reviewed v3 release moves the major reference. Use an exact release tag or full commit SHA instead if the action and its defaults must remain unchanged until you explicitly update the reference.

Before migrating, review the v3 defaults and run a representative test workflow. If you need to preserve a specific library version, set its version input explicitly.

## Configuration

The action has the following parameters:

| Name                           | Description                                                                                                                                                                                                                                                                                         | Required | Default       |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ------------- |
| languages                      | List of languages to be instrumented. Can be either "all" or any of "java", "js", "python", "dotnet", "ruby", "go" (multiple languages can be specified as a space-separated list).                                                                                                                 | true     |               |
| api_key                        | Datadog API key. Can be found at <https://app.datadoghq.com/organization-settings/api-keys>                                                                                                                                                                                                           | true     |               |
| site                           | Datadog site. See <https://docs.datadoghq.com/getting_started/site> for more information about sites.                                                                                                                                                                                                 | false    | datadoghq.com |
| service                        | The name of the service or library being tested.                                                                                                                                                                                                                                                    | false    |               |
| dotnet-tracer-version          | The version of Datadog .NET tracer to use.                                                                                                                                                                                                                                                         | false    | 3.50.0        |
| java-tracer-version            | The version of Datadog Java tracer to use.                                                                                                                                                                                                                                                         | false    | 1.65.1        |
| js-tracer-version              | The version of Datadog JS tracer to use.                                                                                                                                                                                                                                                           | false    | 6.12.0        |
| python-tracer-version          | The version of Datadog Python tracer to use.                                                                                                                                                                                                                                                       | false    | 4.13.1        |
| python-coverage-version        | The version of the Python `coverage` package to use.                                                                                                                                                                                                                                               | false    | 7.15.4        |
| ruby-tracer-version            | The version of datadog-ci Ruby gem to use.                                                                                                                                                                                                                                                         | false    | 1.37.0        |
| go-tracer-version              | The version of Orchestrion to use.                                                                                                                                                                                                                                                                 | false    | v1.12.2       |
| go-module-dir                  | Path to the Go module root directory to instrument. Use this when the repository contains multiple Go modules or the Go module is not in the workspace root.                                                                                                                                       | false    |               |
| java-instrumented-build-system | If provided, only the specified build systems will be instrumented (allowed values are `gradle`,`maven`,`sbt`,`ant`,`all`). `all` is a special value that instruments every Java process. If this property is not provided, all known build systems will be instrumented (Gradle, Maven, SBT, Ant). | false    |               |
| java-tracer-repository-url     | Base URL of a Maven repository (or proxy/mirror) used to download the Java tracer JAR and its sha256. The path under the base must follow the standard Maven layout for `com.datadoghq:dd-java-agent`. Defaults to Maven Central.                                            | false    |               |
| java-tracer-repository-auth-header | Optional HTTP header used to authenticate against `java-tracer-repository-url`, provided as a complete `Name: Value` string (e.g. `Authorization: Bearer <token>`). Only used when `java-tracer-repository-url` is set. Redirects are followed by default; the header will be re-sent on each redirect hop. `curl` strips `Authorization` and `Cookie` headers on cross-origin redirects (different host, port, or scheme), but `wget` does not strip any header. Custom header names (e.g. `X-API-Key`) are never stripped by either tool — prefer the `Authorization: …` form when possible.                       | false    |               |
| java-tracer-auth-disable-redirects | When set to any non-empty value, disables HTTP redirect following for Java tracer downloads that send `java-tracer-repository-auth-header`. Use this if your repository never redirects and you want to guarantee the auth header is only ever sent to the configured `java-tracer-repository-url` host.                                                | false    |               |
| cache                          | Enable caching of downloaded tracers.                                                                                                                                                                                                                                                               | false    | true          |
| print-github-step-summary      | Print a summary of the installed tracers to the GitHub step summary. If set to false, the summary is printed to console instead.                                                                                                                                                                    | false    | true          |

### Pin an individual library version

Set a library's version input to override the default selected by the action release. The explicit version remains in effect when the action reference moves or is updated:

```yaml
- name: Configure Datadog Test Optimization
  uses: datadog/test-visibility-github-action@v3
  with:
    languages: java
    api_key: ${{ secrets.DD_API_KEY }}
    java-tracer-version: 1.64.0
```

This lets you receive action updates while holding a particular library at a version you have validated. That library will not receive automatic bumps, so update the input explicitly when you want a newer version. The same behavior applies to every library-version input in the table above.

Maintainers can use the local scripts described in [RELEASE.md](RELEASE.md) to create a batched library bump PR and publish the resulting action release.

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

By default the Java tracer JAR is fetched from Maven Central (`https://repo1.maven.org/maven2`). Organizations with their own mirror or proxy can point the action at it:

```yaml
- name: Configure Datadog Test Optimization
  uses: datadog/test-visibility-github-action@v3
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
  uses: datadog/test-visibility-github-action@v3
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
