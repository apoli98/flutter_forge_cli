# Flutter Forge CLI

Flutter Forge creates feature-first Flutter apps with Cubit, Bloc, Riverpod, or Provider. It adds clean data, domain, and presentation code and can adopt existing Flutter apps without changing their source. The installed command is `flutter-forge`. Version 0.1.0 is local-only and unpublished.

## Create an app

Use Flutter on your `PATH`. The CLI and generated code require Dart 3.14 or newer. Generated apps require Flutter 3.50 or newer. Verification uses Flutter 3.50.0 and Dart 3.14.0 on macOS.

From this repository:

```sh
dart pub get
dart run bin/flutter_forge.dart create demo --state riverpod
cd demo
flutter run
```

The Home page displays `Welcome to your app`, supplied by `LocalHomeDatasource` at the app composition root. New apps default to iOS and Android, Cubit, the `clean` recipe, and `very_good_analysis`. Select `--state cubit|bloc|riverpod|provider` for the project default. Use `--lint-profile flutter` for Flutter lints, or `--recipe counter` for the counter demo.

Every new app includes a configured Dio client with safe typed errors, app-level GetIt registrations, Freezed and JSON code generation, declared asset folders, and an English Flutter gen-l10n example. Creation runs dependency resolution and code generation. `--no-pub` prints the commands instead. No API endpoints or request logging are generated. Configure `API_BASE_URL` before using the client.

To install the command from the local checkout:

```sh
dart pub global activate --source path .
flutter-forge --help
flutter-forge create my_app --state provider
```

Add Dart's global executable directory to `PATH` if needed. No package has been published, so `dart pub global activate flutter_forge_cli` is not an installation option.

## Use the terminal wizard

```sh
flutter-forge
flutter-forge create
flutter-forge feature --state bloc
flutter-forge create my_app --interactive
```

With terminal input and output, the first command offers create, feature, or init. A create or feature command without a name starts its wizard unless `CI` is set. The wizard asks for omitted values, shows the resolved command, and requires confirmation. Press Enter to accept a displayed default. The confirmation defaults to **no**.

Commands that include a name never prompt unless you pass `--interactive`. Use `--no-interactive` to prohibit prompts, including in a terminal. See the [interactive behavior reference](docs/commands.md#interactive-behavior) for CI rules and cancellation.

## Adopt an existing app

```sh
cd /path/to/existing_flutter_app
flutter-forge init --project-dir . --state riverpod --json
```

`init` reads the package name from `pubspec.yaml` and writes only an absent `flutter_forge.yaml`. It does not run Flutter or change the pubspec, lockfile, analysis options, router, core code, or DI. It detects a `very_good_analysis` include, otherwise it records Flutter lints. Override this with `--lint-profile flutter|very_good`.

Read the missing-dependency warnings and run the exact `flutter pub add` commands manually in your app. Adoption succeeds with warnings, but feature generation refuses missing required dependencies before writing anything. The check covers direct declarations, not resolved versions or SDK compatibility. Existing apps need a compatible Dart SDK and their own datasource adapters. Generated code does not replace an existing domain model or shared failure contract.

Use `flutter-forge init --interactive` for the name-free wizard or `--dry-run` to preview metadata without writes or processes. Repeating init refuses the existing metadata.

For a full scaffold, use `init --scaffold` after declaring its required dependencies, `flutter.generate: true`, and asset directories in pubspec. This adds `lib/main_forge.dart` without replacing your entrypoint, dependency files, or lint configuration. Any occupied generated integration file stops the operation before writes. Run the adopted scaffold with `flutter run -t lib/main_forge.dart`. See the [init reference](docs/commands.md#init) for its preflight requirements.

## Use from an agent or script

```sh
flutter-forge --schema
flutter-forge create --schema --json
flutter-forge --json create my_app --state riverpod --dry-run
flutter-forge create my_app --state provider --no-pub --json
flutter-forge --json feature orders --project-dir /absolute/path/to/my_app --state bloc
```

`--json` never prompts. It writes exactly one JSON object to stdout, including on errors. Read `success`, `exitCode`, and the structured `data` fields. Flutter logs go to stderr. Feature results include `registered`, `registrationStatus`, `updatedFiles`, and manual wiring fields. The [JSON output reference](docs/commands.md#json-output) lists the fields and failure details.

The CLI builds its argument parsers from [`lib/src/cli/commands.json`](lib/src/cli/commands.json). This file defines commands, positional requirements, option types, defaults, and allowed values. Its `$schema` points to [`commands.schema.json`](lib/src/cli/commands.schema.json) for editor validation. After editing command definitions, run `dart run tool/generate_commands.dart` from the repository root and include the updated `commands.g.dart`. The embedded JSON works with `dart run`, global activation, and compiled executables, without reading source files at runtime.

`--schema` returns a Draft 2020-12 JSON Schema for invocation descriptions, derived from those definitions and their argument parsers. Add a command to restrict the schema. Without `--json`, the schema is the raw stdout object. With `--json`, it is in `data.schema`. For example:

```json
{"command":"create","name":"my_app","options":{"state":"riverpod","pub":false,"dry-run":true}}
```

This describes `flutter-forge create my_app --state riverpod --no-pub --dry-run`. Invocation JSON is for discovery and validation only, not accepted as CLI input. Schema validation does not replace runtime checks for reserved names, project state, dependencies, or filesystem safety. See the [invocation JSON Schema reference](docs/commands.md#invocation-json-schema) for option metadata and validation limits.

## Generate a feature

From the generated project:

```sh
flutter-forge feature order_history
flutter-forge feature activity --state bloc --route /account/activity
```

Without global activation, run the CLI from its checkout and pass the app directory:

```sh
dart run bin/flutter_forge.dart feature order_history --project-dir /absolute/path/to/demo
```

Features inherit the project's state choice. An explicit `--state` overrides it for that feature only. Install any override dependencies manually before generation. The CLI never changes your pubspec during feature generation.

New schema-4 apps register features automatically in the Forge-managed router and DI files. The CLI compares both files with their expected generated contents before any write. An edit, missing file, duplicate route, collision, or symlink stops generation. Clean features get an explicitly named local datasource that you replace at the composition root when your adapter is ready. Editing managed composition files ends automatic registration until you restore their generated contents.

To replace a local datasource without losing automatic registration, construct your adapter in app-owned `lib/app/app.dart`. Pass it to the existing `_services = createDependencies(...)` initialization through `homeDatasource`, `orderHistoryDatasource`, or the matching generated feature parameter. `dependencies.dart` stays unchanged. The [composition reference](docs/commands.md#create) describes these public overrides and the intentional refusal when CLI template versions drift.

Legacy schemas 1–3 print `Generated, not registered` and exact constructor wiring instead. For a legacy Cubit project named `demo`, the imports are:

```dart
import 'package:demo/features/order_history/data/datasources/order_history_datasource.dart';
import 'package:demo/features/order_history/data/repositories/order_history_repository_impl.dart';
import 'package:demo/features/order_history/domain/usecases/load_order_history.dart';
import 'package:demo/features/order_history/order_history_route.dart';
import 'package:demo/features/order_history/presentation/order_history_cubit.dart';
```

Implement `OrderHistoryDatasource.load()` in your adapter. Require `OrderHistoryDatasource orderHistoryDatasource` in your router factory and pass the adapter from the app composition root. Add this entry to the existing `GoRouter` routes list:

```dart
orderHistoryRoute(
	createOrderHistoryCubit: () => OrderHistoryCubit(
		LoadOrderHistory(OrderHistoryRepositoryImpl(orderHistoryDatasource)),
	),
),
```

Navigate with `context.go('/order_history')` from a widget that imports `package:go_router/go_router.dart`. The CLI does not add navigation buttons.

The feature contains a datasource interface, a validated starter `id`/`title` model, an immutable entity, a repository, a use case, and loading, loaded, and failed states. Adapt the starter fields to your real domain. A known typed datasource exception becomes a feature-local `fpdart.Either` failure. Unexpected programming errors propagate. No remote endpoint, global GetIt lookup, or production adapter stub is generated. Tests supply fakes and cover failures, retry, and disposal.

Riverpod generates a `Notifier<State>` with a route-local `ProviderScope` override and automatic disposal. No app-wide scope is required for the generated route. Provider generates a `ChangeNotifier` owned by the route's `ChangeNotifierProvider`. Both use the same clean domain/data layers as Cubit and Bloc.

App package names cannot match required dependencies. Riverpod also reserves `riverpod`, the transitive package pinned by `flutter_riverpod`. Other backends do not reserve that name. Feature names remain independent of package exports, so `change` with Provider and `stream` with Riverpod are valid.

New apps and explicit scaffold adoption use schema 4 with a typed feature registry. Metadata-only init keeps schema 3 and manual registration. Schemas 1 and 2 retain Cubit as their feature default. Schema 1 also keeps the counter recipe and Flutter lint profile. Legacy feature generation never upgrades metadata. Managed feature generation updates only the registry, router, DI, and new feature files. Static `--route` overrides work for both recipes and all four backends.

Run the generated tests:

```sh
flutter analyze
flutter test
```

See [command reference](docs/commands.md) for defaults and failure behavior, and [architecture](docs/architecture.md) for file ownership.

## Verify the CLI

```sh
dart pub get
dart format --output=none --set-exit-if-changed bin lib test tool
dart analyze --fatal-infos
dart test
dart run tool/verify_flutter.dart /absolute/path/to/existing/temp-parent
```

The verification script retains disposable iOS and Android apps under the supplied parent. It covers all four backends, both recipes, and both lint profiles. It runs real Freezed, JSON, and localization generation, then checks automatic route navigation, DI registration, edited-file refusal, cross-backend wiring, business-name collisions, legacy metadata, and both adoption modes. It runs Flutter unit and widget tests, not device or web builds. It needs network access for uncached packages. On this machine the approved parent is `/private/var/folders/f7/wgd6hcg910383s9x8pbnzq200000gp/T/opencode`.

To rerun a failed portion without repeating completed apps, set `FORGE_VERIFY_FROM` to its printed app name, such as `verified_very_good_counter_cubit`. This starts a fresh partial run from that matrix selection, still checks legacy metadata and adoption, and labels its result as partial. `FORGE_VERIFY_FROM=legacy` runs only the compatibility and adoption checks.
