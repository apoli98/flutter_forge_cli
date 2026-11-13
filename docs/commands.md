# Command reference

## Global options

`flutter-forge --help` prints usage. `flutter-forge --version` prints `flutter-forge 0.1.0`. Both bypass prompts, including with `--interactive` and without a terminal. Unknown arguments still fail parsing.

Common flags are `--help`, `-h`, `--version`, `--interactive`, `--no-interactive`, `--json`, and `--dry-run`. They work before or after the subcommand. Command-specific options remain after the subcommand.

## Interactive behavior

Automatic prompting requires both stdin and stdout to be terminals, no active `CI` indicator, and either no arguments or `create` or `feature` without a positional name. With no arguments, the wizard offers a numbered command choice. A nonempty `CI` value disables automatic prompting unless its trimmed, case-insensitive value is `false` or `0`.

- A command with a name never prompts automatically, even when some options use defaults.
- `--interactive` explicitly starts the wizard and overrides `CI`. It requires terminal stdin and stdout. Without them, the CLI exits with code `64` and explains how to use explicit arguments.
- `--no-interactive` guarantees no prompts. A missing command or name exits with code `64`. The name is positional, not a `--name` flag. Other options have defaults.
- `--json` also disables prompts. Combining `--interactive` with either `--json` or `--no-interactive` exits with code `64`.
- With no arguments in a nonterminal or CI environment, the CLI prints help and exits with code `0`.
- Invalid arguments, unknown options, and extra positional arguments fail before prompting.

The create wizard collects an omitted name, organization, platforms, output parent, and dependency-fetch choice. The feature wizard collects an omitted name, project directory, and Cubit or Bloc choice. Explicit options, including `--no-pub`, are retained without prompts. `--dry-run` is never prompted for.

Text prompts accept Enter for displayed defaults. Numbered selectors also accept the displayed option text. Invalid names, dependency-conflicting app names, organizations, platforms, selected paths, and selector input are retried. Invalid values supplied as arguments fail instead of being replaced.

Before generation, the wizard shows the resolved command and all relevant options. Confirmation defaults to no. Declining or reaching EOF exits with code `130` without writes or subprocesses. Ctrl-C uses normal terminal interruption. No writes or subprocesses start before confirmation. The complete collision and scaffold preflight still runs after collection. Confirmation does not bypass any safety checks.

## JSON output

`--json` emits exactly one JSON object followed by a newline on stdout. Help, version, dry runs, successful generation, and handled errors use the same envelope. No terminal is needed. Flutter subprocess stdout and stderr both go to CLI stderr.

The schema has these stable top-level fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `schemaVersion` | integer | Always `1`. |
| `success` | boolean | Whether `exitCode` is `0`. |
| `exitCode` | integer | Same as the process exit code. |
| `command` | string or null | `create`, `feature`, or null before command selection or when parsing fails. |
| `data` | object | Operation-specific fields, or available context on failure. |
| `error` | object or null | On failure, `kind` and `message` strings. Otherwise null. |

Error kinds are `usage`, `filesystem`, `process`, and `cancelled`. Agents can branch on these fields without parsing human messages. Abrupt OS termination cannot guarantee a JSON result.

Operation data fields are:

- Create: `operation: "create"`, `name`, absolute canonical `target`, `org`, `platforms` as a string list, `pub`, and `dryRun`. `flutterCreateArguments` contains the Flutter argument list after successful preflight.
- Feature: `operation: "feature"`, `name`, absolute canonical `projectRoot`, `state`, `dryRun`, and `registered: false`. The `wiring` object contains `routerFile`, `imports` as a string list, `routeEntry`, and `location`. Registration remains manual.
- A successful dry run adds `plannedFiles`. Successful generation adds `generatedFiles`. Both lists use relative template paths under `target` or `projectRoot`. Flutter also produces platform files, which are not included in these lists.
- A staged create failure adds `failedStage`, `partialOutput` as a boolean, and `scaffoldComplete` as a boolean. Failed dependency resolution also adds `retryArguments: ["flutter", "pub", "get"]`, to run in `target`. A filesystem error during feature writes adds `partialOutput: true`. Preflight failures do not imply new partial output.
- Help: `operation: "help"`, `version`, `usage` text, `commands`, and `options` lists. Version: `operation: "version"` and `version`.

Fields become available as validation progresses. An early usage or filesystem failure can have empty `data`.

Example dry-run result, with the file list shortened here:

```json
{
	"schemaVersion": 1,
	"success": true,
	"exitCode": 0,
	"command": "feature",
	"data": {
		"operation": "feature",
		"name": "orders",
		"projectRoot": "/work/my_app",
		"state": "cubit",
		"dryRun": true,
		"registered": false,
		"wiring": {
			"routerFile": "lib/app/router.dart",
			"imports": [
				"import '../features/orders/orders_route.dart';",
				"import '../features/orders/presentation/orders_cubit.dart';"
			],
			"routeEntry": "ordersRoute(createOrdersCubit: OrdersCubit.new),",
			"location": "/orders"
		},
		"plannedFiles": ["lib/features/orders/orders_route.dart"]
	},
	"error": null
}
```

## Create

```text
flutter-forge create <name> [--org com.example] [--platforms ios,android]
  [--output .] [--dry-run] [--no-pub]
```

- `name` is a nonreserved lowercase snake_case Dart name. Each underscore-separated segment must start with a letter. Digits are allowed after that letter, so `order1` and `http2_client` are valid, but `order_1` and `http_2_client` are not.
- App names cannot match a bundled direct runtime or development dependency. These names include `flutter_bloc`, `go_router`, `material_ui`, `bloc_test`, and `flutter_lints`. Validation also applies with `--dry-run` or `--no-pub`, before any files or processes are created.
- `--org` is a lowercase reverse-domain organization with at least two segments.
- `--platforms` accepts unique comma-separated values from `android`, `ios`, `web`, `macos`, `windows`, and `linux`. The default is `ios,android`.
- `--output` is an existing parent directory. The default is the current directory. The target is `<output>/<name>` and must not exist, even as a dangling symbolic link.
- `--dry-run` validates inputs and output paths, then prints the Flutter command and template file list. It writes no files and starts no processes.
- `--no-pub` omits the final `flutter pub get`.

The CLI starts `flutter create --empty --no-pub --project-name <name> --org <org> --platforms <platforms> <target>`. It then replaces only the fresh scaffold's `lib/main.dart`, `pubspec.yaml`, and `test/widget_test.dart`, and writes new template files. There is no general overwrite option.

Generated dependencies are `flutter_bloc ^9.1.1`, `go_router ^18.1.4`, and `material_ui ^1.11.0`. Flutter 3.50 deprecates its former Material library export, so generated code imports the official `material_ui` package directly. Development dependencies include `bloc_test ^10.0.0`, `flutter_lints ^6.0.0`, and the Flutter test SDK. Dependency versions are bundled, not fetched from the pub API during generation. `flutter pub get` resolves them unless disabled.

Flutter is discovered on `PATH`. Activate an FVM environment or put its Flutter executable on `PATH` before invoking the CLI.

## Feature

```text
flutter-forge feature <name> [--project-dir .] [--state cubit|bloc] [--dry-run]
```

- `name` follows the same segment rules as app names. The app-specific dependency-name restriction does not apply to features, so names such as `go_router` and `bloc_test` are permitted.
- `--project-dir` selects an existing Flutter Forge project. The default is the current directory.
- `--state` defaults to `cubit`.
- `--dry-run` checks the same collisions as a real invocation without writing files or starting processes.

The project must have `flutter_forge.yaml` with `schema_version: 1` and `package` matching `pubspec.yaml`. Its pubspec must declare the Flutter SDK dependency. Other projects and schema versions are rejected. This marker is compatibility metadata, not an authenticity check or migration tool.

The directories `lib/features/<name>` and `test/features/<name>` must both be absent, even if an existing directory is empty. The CLI preflights every output path before writing. Feature generation never changes the router, dependency setup, pubspec, or metadata. It prints the exact imports and route-list entry to add manually.

Selected project and output root aliases are canonicalized, which permits macOS `/var` aliases. Symbolic links inside the generated output paths are rejected.

## Exit codes and interrupted generation

- `0` means success, help, version, or a successful dry run.
- `64` means invalid usage, invalid identifiers, or an unsupported or malformed project.
- `1` means a filesystem or Flutter subprocess failure.
- `130` means the wizard was cancelled before generation.

On Flutter failure, the CLI identifies the failed stage and reports whether target output remains. Failed `flutter pub get` leaves the complete scaffold and prints a retry instruction. Failed `flutter create` can leave only part of Flutter's own scaffold.

Multi-file writes are not atomic. A crash, permission error, or full disk can leave a partial feature or app. The CLI does not roll back or delete output. Inspect the reported directory before retrying. App creation requires an absent target, and feature generation refuses existing feature directories. Preserve any work before manually moving or removing partial output.

Concurrent writers are unsupported. Preflight and exclusive creation protect ordinary use, not races with other processes changing directories or links during a write. Generation is for a trusted local workspace, not a sandbox for hostile concurrent filesystem changes.
