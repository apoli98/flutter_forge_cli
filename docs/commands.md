# Command reference

## Global options

`flutter-forge --help` prints usage. `flutter-forge --version` prints `flutter-forge 0.1.0`. `flutter-forge --schema` prints an invocation JSON Schema. These discovery flags bypass prompts, including with `--interactive` and without a terminal. Unknown arguments still fail parsing. If combined, version takes precedence over help, then schema.

Common flags are `--help`, `-h`, `--version`, `--schema`, `--interactive`, `--no-interactive`, `--json`, and `--dry-run`. They work before or after the subcommand. Command-specific options remain after the subcommand.

## Interactive behavior

Automatic prompting requires both stdin and stdout to be terminals, no active `CI` indicator, and either no arguments or `create` or `feature` without a positional name. With no arguments, the wizard offers a numbered command choice. A nonempty `CI` value disables automatic prompting unless its trimmed, case-insensitive value is `false` or `0`.

- A command with a name never prompts automatically, even when some options use defaults.
- `init` takes no name and never prompts automatically. The no-argument chooser and `init --interactive` collect its directory, state management, recipe, and lint profile.
- `--interactive` explicitly starts the wizard and overrides `CI`. It requires terminal stdin and stdout. Without them, the CLI exits with code `64` and explains how to use explicit arguments.
- `--no-interactive` guarantees no prompts. A missing command or name exits with code `64`. The name is positional, not a `--name` flag. Other options have defaults.
- `--json` also disables prompts. Combining `--interactive` with either `--json` or `--no-interactive` exits with code `64`.
- With no arguments in a nonterminal or CI environment, the CLI prints help and exits with code `0`.
- Invalid arguments, unknown options, and extra positional arguments fail before prompting.

The create wizard collects an omitted name, organization, platforms, output parent, dependency-fetch choice, state management, recipe, and lint profile. The feature wizard collects an omitted name, project directory, and state management. State selectors offer Cubit, Bloc, Riverpod, and Provider. The feature selector defaults to the project's state choice. Feature recipe, lint, and route overrides are explicit flags. Explicit options, including `--no-pub`, are retained without prompts. `--dry-run` is never prompted for.

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
| `command` | string or null | `create`, `feature`, `init`, or null before command selection or when parsing fails. |
| `data` | object | Operation-specific fields, or available context on failure. |
| `error` | object or null | On failure, `kind` and `message` strings. Otherwise null. |

Error kinds are `usage`, `filesystem`, `process`, and `cancelled`. Agents can branch on these fields without parsing human messages. Abrupt OS termination cannot guarantee a JSON result.

Operation data fields are:

- Create: `operation: "create"`, `name`, absolute canonical `target`, `org`, `platforms` as a string list, `pub`, and `dryRun`. `flutterCreateArguments` contains the Flutter argument list after successful preflight.
- Feature: `operation: "feature"`, `name`, absolute canonical `projectRoot`, `state`, `dryRun`, and `registered`. `registrationStatus` is `planned`, `registered`, or `manual`. Managed success reports the existing files changed in `updatedFiles`. Legacy schemas keep manual registration. The `wiring` object provides the manual constructor contract in either case.
- Create, init, and feature expose the resolved `state`, `recipe`, and `lintProfile`.
- Init exposes `operation: "init"`, the pubspec-derived `name`, canonical `projectRoot`, `dryRun`, and `warnings`. Init and feature expose `missingDependencies` with `dependencies`, `devDependencies`, exact manual `commands`, and check `scope`.
- Wiring also includes `controllerExpression` and `text`. Clean wiring includes `requiredParameter` for the injected datasource and `datasourceContract`. Text and JSON derive from one model.
- A successful dry run adds `plannedFiles`. Successful generation adds `generatedFiles`. Both lists use relative template paths under `target` or `projectRoot`. Flutter also produces platform files, which are not included in these lists.
- Managed operations report `requiredCommands` as argument lists and `codeGeneration` as `requested`, `required`, or `complete`. `--no-pub` reports the commands without starting them. A dry run never starts them either.
- A staged create failure adds `failedStage`, `partialOutput` as a boolean, and `scaffoldComplete` as a boolean. A generation failure also adds the failed command as `retryArguments`, to run in `target`. A filesystem error during feature writes or a process error after writes adds `partialOutput: true`. Preflight failures do not imply new partial output.
- Help: `operation: "help"`, `version`, `usage` text, `commands`, and `options` lists. Version: `operation: "version"` and `version`.
- Schema: `operation: "schema"` and `schema`, containing the invocation JSON Schema described below.

Fields become available as validation progresses. An early usage or filesystem failure can have empty `data`.

Example schema v1 counter-project dry-run result, with fields shortened here:

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
				"import 'package:my_app/features/orders/orders_route.dart';",
				"import 'package:my_app/features/orders/presentation/orders_cubit.dart';"
			],
			"routeEntry": "ordersRoute(createOrdersCubit: OrdersCubit.new),",
			"location": "/orders"
		},
		"plannedFiles": ["lib/features/orders/orders_route.dart"]
	},
	"error": null
}
```

## JSON command definitions

[`lib/src/cli/commands.json`](../lib/src/cli/commands.json) is the source for command names, positional requirements, options, types, defaults, allowed values, abbreviations, and option help. `commonOptions` applies at both the root and command levels. Each command lists its `positionals` in order and its command-specific `options`. String options accept one value. Boolean options are flags, default to false, and permit `--no-<name>` unless `negatable` is false.

The document's `$schema` references [`commands.schema.json`](../lib/src/cli/commands.schema.json). The typed Dart loader also rejects unknown keys, duplicate command or option names, abbreviation or negation collisions, invalid defaults, and required positionals after optional ones. Defaults must match their option type and, when present, its allowed values. Positional names cannot be `command` or `options`, which the invocation schema reserves.

After a definitions edit, `dart run tool/generate_commands.dart` regenerates `lib/src/cli/commands.g.dart` from the repository root. Tests check that the embedded text and generated file match the JSON. Runtime parsers decode the embedded JSON rather than load a file relative to the current directory or executable. Rebuild compiled executables or reactivate an installed snapshot after changes. Command dispatch, interactive collection, inheritance, and semantic validation remain Dart code. Adding an executable command still requires its Dart handler.

## Invocation JSON Schema

```sh
flutter-forge --schema
flutter-forge create --schema
flutter-forge feature --schema --json
flutter-forge init --schema
```

`--schema` emits a JSON Schema using Draft 2020-12. Without `--json`, stdout contains only the raw schema object and one newline. With `--json`, the normal result envelope contains `data.operation: "schema"` and `data.schema`. The envelope's `command` is the selected command, or null for the full schema. Discovery never prompts, writes files, or starts subprocesses.

The full schema has one `oneOf` branch per supported command. A command-specific request includes only that command's branch. Invocation objects require `command`. Create and feature also require a string `name`, representing the positional argument. Init forbids `name`. The optional `options` object uses the CLI's long kebab-case names without `--`. Unknown top-level fields, unknown options, and options from other commands are rejected.

Example invocation description:

```json
{
	"command": "create",
	"name": "my_app",
	"options": {
		"state": "riverpod",
		"lint-profile": "flutter",
		"pub": false,
		"dry-run": true,
		"json": true
	}
}
```

This describes `flutter-forge create my_app --state riverpod --lint-profile flutter --no-pub --dry-run --json`. The CLI does **not** accept invocation JSON as input. Consumers must translate validated descriptions to command-line arguments.

Option types, enum choices, descriptions, and defaults come from the JSON-backed argument parsers. Positional fields and requirements come from the same command definitions. A missing `default` means the parser declares none. The schema does not invent runtime defaults, inherited project values, detected lint profiles, or computed routes. For example, `state` has no parser default, although create resolves it to Cubit at runtime. Parser defaults are annotations, not instructions to insert values into an invocation.

Flags use JSON booleans. A false negatable flag such as `pub: false` maps to `--no-pub`. A false nonnegatable flag means omit that flag. Per-option `x-cli` metadata contains `flag`, `abbr` when present, and `negatable` for flags. Negatable flags also expose `negatedFlag`. The name's `x-cli.position` is the zero-based positional index after the command.

Invocation options include `interactive`, `no-interactive`, `json`, and `dry-run`. The schema rejects `interactive: true` combined with either `json: true` or `no-interactive: true`. A terminal is still required for interactive execution. Discovery flags `help`, `version`, and `schema` are excluded from invocation options because they do not execute the described command. Their parser-derived definitions remain available in the root `x-cli.discoveryOptions` object, including the `h` abbreviation for help.

Schema validation checks invocation structure, types, enums, and interactive flag conflicts. It does not replace runtime validation of names and reserved words, organizations, platforms, routes, project metadata, dependencies, or filesystem safety. A schema-valid invocation can still fail these checks. Use `--dry-run` with normal CLI arguments for runtime preflight without writes or processes.

## Create

```text
flutter-forge create <name> [--org com.example] [--platforms ios,android]
  [--output .] [--dry-run] [--no-pub]
  [--recipe clean|counter] [--lint-profile auto|flutter|very_good]
  [--state cubit|bloc|riverpod|provider]
```

- `name` is a nonreserved lowercase snake_case Dart name. Each underscore-separated segment must start with a letter. Digits are allowed after that letter, so `order1` and `http2_client` are valid, but `order_1` and `http_2_client` are not.
- App names cannot match a direct dependency used by the selected state management, recipe, and lint profile. Riverpod also reserves `riverpod` because `flutter_riverpod` requires that transitive package. This reservation does not add a direct dependency. Validation also applies with `--dry-run` or `--no-pub`, before any files or processes are created. Unused optional dependencies do not reserve names.
- `--state` defaults to `cubit` and records the project's feature default.
- The default recipe is `clean`. `counter` selects the increment demo. `auto` resolves to `very_good` for new apps.
- `--org` is a lowercase reverse-domain organization with at least two segments.
- `--platforms` accepts unique comma-separated values from `android`, `ios`, `web`, `macos`, `windows`, and `linux`. The default is `ios,android`.
- `--output` is an existing parent directory. The default is the current directory. The target is `<output>/<name>` and must not exist, even as a dangling symbolic link.
- `--dry-run` validates inputs and output paths, then prints the Flutter command and template file list. It writes no files and starts no processes.
- `--no-pub` omits dependency resolution and all code generation. It prints the required commands instead.

The CLI starts `flutter create --empty --no-pub --project-name <name> --org <org> --platforms <platforms> <target>`. It replaces only the fresh scaffold's `lib/main.dart`, `pubspec.yaml`, `analysis_options.yaml`, and `test/widget_test.dart`, and writes new template files. There is no general overwrite option.

Shared dependencies are the Flutter SDK, `go_router ^18.1.4`, and `material_ui ^1.11.0`. Cubit and Bloc add `flutter_bloc ^9.1.1` and development dependency `bloc_test ^10.0.0`. Riverpod adds `flutter_riverpod ^3.5.0`. Provider adds `provider ^6.1.5+1`. Neither notifier backend includes Bloc packages. Clean adds `fpdart ^1.2.0`. All choices include the Flutter test SDK and either `very_good_analysis ^11.0.0` or `flutter_lints ^6.0.0`. Flutter 3.50 uses the official `material_ui` package. Generated code requires Dart 3.14 concise constructors. Dependency versions are bundled. `flutter pub get` resolves them unless disabled.

New apps use schema 4 and include Dio, GetIt, Freezed, JSON serialization, assets, and English localizations for every state backend and recipe. Clean models use Freezed and checked JSON mapping. Clean states and Bloc events use Freezed unions. Counter values remain immutable integers for notifier backends and Freezed state for Bloc backends.

The app composition root registers the configured Dio client and feature factories. Features use constructor injection and never look up GetIt. Clean features use an explicitly named local starter datasource. There are no generated endpoints, requests, credentials, request loggers, or pretend remote adapters. `API_BASE_URL` defaults to empty. The typed client refuses requests until a base URL is configured.

`createDependencies` exposes an optional datasource parameter for every clean feature, including `homeDatasource` and, after generating `orders`, `ordersDatasource`. A supplied instance replaces that feature's local starter adapter. The app-owned `lib/app/app.dart` initializes `_services` with `createDependencies()`. Construct your adapter there and pass it through the matching datasource parameter. Import the adapter in `app.dart`, not in managed `dependencies.dart`. Features still receive their repository, use case, and controller dependencies through constructors. The `apiConfig` parameter accepts an app-owned `ApiConfig` when compile-time `API_BASE_URL` is not suitable.

Managed commands run these steps in the project directory unless `--no-pub` is supplied:

```sh
flutter pub get
flutter gen-l10n
flutter pub run tool/fix_localization_imports.dart
flutter pub run build_runner build
```

The import script replaces Flutter 3.50 gen-l10n's deprecated localization re-exports with the supported standalone UI packages. It changes imports only and does not disable analyzer diagnostics. Run it after each manual `flutter gen-l10n`. Asset directories `assets/images/` and `assets/icons/` are declared in pubspec. `AppLocalizations` supplies the app title. A widget test also verifies the English greeting through the installed localization delegate.

Flutter is discovered on `PATH`. Activate an FVM environment or put its Flutter executable on `PATH` before invoking the CLI.

## Feature

```text
flutter-forge feature <name> [--project-dir .] [--state cubit|bloc|riverpod|provider] [--dry-run]
  [--recipe clean|counter] [--lint-profile auto|flutter|very_good] [--route /path] [--no-pub]
```

- `name` follows the same segment rules as app names. The app-specific dependency-name restriction does not apply to features, so names such as `go_router`, `change`, and `stream` are permitted. Generated backend and UI imports use prefixes to avoid controller-name collisions.
- `--project-dir` selects an existing Flutter Forge project. The default is the current directory.
- `--state` inherits the persisted project default. An override affects only this feature and requires its own runtime and test dependencies. Missing declarations block generation and produce manual install commands. The selected backend's app-package name checks also apply, including Riverpod's transitive `riverpod` reservation.
- `--dry-run` checks the same collisions as a real invocation without writing files or starting processes.
- Recipe and lint profile default to metadata values. An explicit `auto` detects a Very Good Analysis include, otherwise Flutter lints. Overrides do not change the project's defaults or analysis options. Managed feature entries record their own state and recipe.
- `--route` defaults to `/<name>`. Only `/` or absolute segments containing letters, digits, underscores, and hyphens are accepted. Parameters, queries, fragments, quotes, escapes, repeated slashes, and trailing slashes are rejected before writes. Managed apps reject duplicate names, generated symbols, and case-insensitive routes. Legacy projects require manual route checks.

The project must have `flutter_forge.yaml` with `package` matching a Flutter pubspec. Schema v1 supports exactly `schema_version` and `package`, and reads as counter with Flutter lints and Cubit. Schema v2 also requires `recipe: clean|counter` and `lint_profile: flutter|very_good`, and keeps Cubit. Schema v3 adds `state: cubit|bloc|riverpod|provider`. These legacy schemas retain manual registration and do not change metadata or run code generation. Schema v4 adds a typed `features` registry with `name`, `state`, `recipe`, and `route` per entry. Unknown fields and malformed entries fail before writes. Required direct runtime and test dependencies must be declared before feature generation.

The directories `lib/features/<name>` and `test/features/<name>` must both be absent, even if an existing directory is empty. The CLI preflights every output path before writing. For schema 4 it renders the existing router and DI files from the typed registry and compares their exact contents with disk. Any missing, edited, unknown, or linked integration file stops the entire operation before new files appear. Successful registration rewrites only `lib/app/router.dart`, `lib/app/dependencies.dart`, and `flutter_forge.yaml`. No force or overwrite flag exists. To take over these files, stop using automatic feature registration and register new features manually.

This comparison is tied to the installed CLI's templates. A template change in a newer CLI can refuse integration files from an older generator even when you have not edited them. That stop is intentional. Keep the matching CLI version or review and migrate the composition files manually. There is no automatic overwrite or migration for template drift.

Managed code generation also requires exact generated `l10n.yaml`, `build.yaml`, and `tool/fix_localization_imports.dart` contents. Custom localization output directories, builder output extensions, and root `build.*.yaml` or `*.build.yaml` overrides are refused. The configured builders process only `lib/features/**.dart`. Before any feature writes, the CLI rejects symlinks throughout default source roots, localization outputs, and `.dart_tool/build`, including dangling links. It checks package metadata output paths too. The same check runs again before the first Flutter command because dependency resolution can generate localizations. These restrictions also apply to `--no-pub` and dry runs.

Localization build metadata under `build/<32-hex-hash>/` also has link checks, including its JSON, depfile, stamp, file cache, and output manifest. A linked `build` root, `.last_build_id` marker, or hash directory is refused. Unrelated native output subtrees are not traversed or changed by this check. Regular Flutter build-cache contents remain trusted.

This preflight bounds the bundled generator configuration. It is not a sandbox for dependency-supplied build scripts, hostile concurrent filesystem changes, or custom builders. Dependencies remain trusted executable code. Existing regular generated parts are not treated as user-owned source; build_runner can regenerate them. Do not put handwritten changes in generated localization or part files.

Selected project and output root aliases are canonicalized, which permits macOS `/var` aliases. Symbolic links inside the generated output paths are rejected.

## Init

```text
flutter-forge init [--project-dir .] [--recipe clean|counter]
  [--lint-profile auto|flutter|very_good] [--dry-run]
  [--state cubit|bloc|riverpod|provider] [--scaffold] [--no-pub]
```

Init accepts no positional name. The name comes from a valid pubspec with a `flutter: {sdk: flutter}` dependency. It writes only an absent `flutter_forge.yaml` through the normal safe writer. Existing metadata, including dangling symlinks, is refused. It does not run a subprocess or write source, pubspec, lockfile, analysis options, router, core, or DI files.

`--scaffold` explicitly adds the full schema-4 scaffold to an existing app. It creates `lib/main_forge.dart` and `test/forge_widget_test.dart` instead of replacing the app's existing entrypoint or test. It never rewrites pubspec or analysis options. Required direct dependencies must already be declared, with `flutter.generate: true` and asset entries `assets/images/` and `assets/icons/`. Missing declarations or an occupied integration path stop before any write. This includes an existing `lib/app/router.dart`, `lib/app/dependencies.dart`, `l10n.yaml`, or generated feature directory. After successful adoption, the alternate entrypoint runs with `flutter run -t lib/main_forge.dart`. Dependency resolution and code generation run unless `--no-pub` is supplied.

The default recipe is clean and the default state management is Cubit. Init records the explicit state selection, not a guess from installed dependencies. Auto detects `include: package:very_good_analysis/...` in `analysis_options.yaml`, otherwise Flutter lints. Missing required declarations produce structured warnings and exact manual `flutter pub add` commands, but metadata adoption succeeds. Feature generation blocks until its required declarations exist. Init does not promise that a generated starter replaces an app's existing API schema, entities, or failure model.

## Exit codes and interrupted generation

- `0` means success, help, version, or a successful dry run.
- `64` means invalid usage, invalid identifiers, or an unsupported or malformed project.
- `1` means a filesystem or Flutter subprocess failure.
- `130` means the wizard was cancelled before generation.

On Flutter failure, the CLI identifies the failed stage and reports whether target output remains. Failed `flutter pub get` leaves the complete scaffold and prints a retry instruction. Failed `flutter create` can leave only part of Flutter's own scaffold.

Multi-file writes are not atomic. A crash, permission error, or full disk can leave a partial feature or app. The CLI does not roll back or delete output. Inspect the reported directory before retrying. App creation requires an absent target, and feature generation refuses existing feature directories. Preserve any work before manually moving or removing partial output.

Concurrent writers are unsupported. Preflight and exclusive creation protect ordinary use, not races with other processes changing directories or links during a write. Generation is for a trusted local workspace, not a sandbox for hostile concurrent filesystem changes.
