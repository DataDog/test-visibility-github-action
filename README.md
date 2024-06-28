![logo](CIVislogo.png)

# Datadog Test Visibility GitHub Action

GitHub Action that installs [Datadog Test Visibility](https://docs.datadoghq.com/tests/). 
Supported languages are .NET, Java, Javascript, and Python.

## About Datadog Test Visibility

[Test Visibility](https://docs.datadoghq.com/tests/) provides a test-first view into your CI health by displaying important metrics and results from your tests. 
It can help you investigate and mitigate performance problems and test failures that are most relevant to your work, focusing on the code you are responsible for, rather than the pipelines which run your tests.

## Usage

1. Set [Datadog API key](https://app.datadoghq.com/organization-settings/api-keys) inside Settings > Secrets as `DD_API_KEY`.
2. Add a step to your GitHub Actions workflow YAML that uses this action. Set the language, service name and [site](https://docs.datadoghq.com/getting_started/site/) parameters. It is best if the new step comes right before the step that runs your tests: 

   ```yaml
   steps:
     - name: Configure Datadog Test Visibility
       uses: datadog/test-visibility-github-action@v1
       with:
         languages: java
         service-name: my-service
         api-key: ${{ secrets.DD_API_KEY }}
         site: US1
     - name: Run unit tests
       run: |
         mvn clean test
   ```

## Configuration

The action has the following parameters:

```yaml
languages: List of languages to be instrumented. Can be either "all" or any of "java", "js", "python", "dotnet" (multiple languages can be specified as a space-separated list).
service-name: The name of the service or library being tested.
api-key: Datadog API key. Can be found at https://app.datadoghq.com/organization-settings/api-keys
site: Datadog site (optional), defaults to US1. See https://docs.datadoghq.com/getting_started/site for more information about sites.
```
