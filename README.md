# Flutter Forge CLI

**Create feature-first Flutter apps. Add features without repeating the setup.**

Flutter Forge generates apps and features with **Cubit, Bloc, Riverpod, or Provider**, plus routing, dependency injection, tests, and code generation. Start a new project or adopt an existing Flutter app.

[Get started](#get-started) · [Add a feature](#3-add-a-feature) · [Command reference](docs/commands.md) · [Architecture](docs/architecture.md)

> **Early release · v0.1.0**
> Install from this repository. Flutter Forge is not published on pub.dev.

## Get started

### 1. Install the CLI

Requirements: **Dart 3.14+** and **Flutter 3.50+**, with `dart` and `flutter` on your `PATH`.

```sh
git clone https://github.com/apoli98/flutter_forge_cli.git
cd flutter_forge_cli
dart pub global activate --source path .
flutter-forge --help
```

If `flutter-forge` is not found, add Dart's global executable directory to your `PATH`. The default on macOS and Linux is `$HOME/.pub-cache/bin`.

### 2. Create an app

From the directory where you want to keep your apps:

```sh
flutter-forge create my_app --state riverpod
cd my_app
flutter run
```

Creation resolves dependencies and runs localization and code generation. The generated Home page displays **Welcome to your app**.

Choose `--state cubit`, `--state bloc`, `--state riverpod`, or `--state provider`. New apps default to Cubit, iOS and Android, the `clean` recipe, and `very_good_analysis`.

To select another setup:

```sh
flutter-forge create counter_app --recipe counter --state bloc
flutter-forge create web_app --platforms web --lint-profile flutter
```

Use `--dry-run` to preview without writes or subprocesses. Use `--no-pub` to generate files and print the dependency and code-generation commands without running them.

### 3. Add a feature

Inside your generated app:

```sh
flutter-forge feature orders
flutter-forge feature activity --route /account/activity
```

Features inherit the project's state management. New Forge apps register their routes and dependencies automatically. Navigate to the generated route from your app; the CLI does not add navigation buttons.

An explicit `--state` changes the backend for that feature only. Install any additional backend dependencies before generation. The CLI does not edit your pubspec when adding a feature.

## What you get

The default `clean` recipe separates each feature into data, domain, and presentation code, with constructor injection between layers.

| Area | Generated setup |
| --- | --- |
| State management | Cubit, Bloc, Riverpod `Notifier`, or Provider `ChangeNotifier` |
| Feature layers | Datasource contract, model, entity, repository, use case, controller, and page |
| Navigation | GoRouter routes with feature-local state ownership |
| Dependencies | App-level GetIt composition, without service lookups inside features |
| Networking | Dio client with typed errors and an explicit base URL configuration |
| Code generation | Freezed and JSON serialization |
| App resources | English Flutter localizations and declared image and icon asset folders |
| Tests | Generated feature tests and an app widget test |

The starter datasource is local, not a pretend API integration. Replace it with your adapter at the app composition root. No API endpoints, credentials, or request logging are generated. Configure `API_BASE_URL` before using the network client.

For a smaller increment demo, choose `--recipe counter`. See [generated app architecture](docs/architecture.md#generated-application) for ownership and dependency flow.

## Use the terminal wizard

```sh
flutter-forge
```

Choose a command, fill in omitted values, and review the resolved command before confirming. Confirmation defaults to **no**.

You can also run `flutter-forge create` or `flutter-forge feature` without a name to start their wizards in a terminal. Commands with a name do not prompt unless you pass `--interactive`. Use `--no-interactive` for scripts, or `--json` for structured output.

## Adopt an existing app

From an existing Flutter project:

```sh
flutter-forge init --state riverpod
```

By default, `init` writes only `flutter_forge.yaml`. It does not change source, dependency files, or lint configuration. Follow any printed dependency-install commands before generating features. Metadata-only adoption requires manual route and dependency registration.

To add the full managed scaffold, use `init --scaffold` after completing its dependency and pubspec requirements. It adds `lib/main_forge.dart` without replacing your entrypoint. Read the [adoption requirements](docs/commands.md#init) before using this mode.

## Automate with JSON

```sh
flutter-forge create my_app --state riverpod --dry-run --json
flutter-forge feature orders --project-dir /path/to/my_app --json
flutter-forge --schema > commands.schema.json
```

`--json` disables prompts and emits one JSON result on stdout, including handled errors. Read `success`, `exitCode`, `data`, and `error` instead of parsing terminal messages. Flutter subprocess logs go to stderr.

`--schema` exports a Draft 2020-12 JSON Schema for command invocation descriptions. The CLI still takes command-line arguments, not JSON input.

The CLI itself builds its parsers from [`commands.json`](lib/src/cli/commands.json), validated by [`commands.schema.json`](lib/src/cli/commands.schema.json). See the [JSON command definitions](docs/commands.md#json-command-definitions) and [JSON output reference](docs/commands.md#json-output).

## Know the safety boundaries

- New app targets and feature directories must be absent. There is no force-overwrite flag.
- Automatic registration checks Forge-managed router and dependency files before writing. Edited, missing, or linked integration files stop generation.
- Older metadata-only projects keep manual registration. Feature generation does not silently upgrade them.
- Filesystem checks do not make writes atomic. An interrupted write or failed subprocess can leave partial output. Inspect it before retrying.

Keep custom datasource adapters in app-owned code and pass them through the generated composition API. See [composition overrides](docs/commands.md#create) and [failure behavior](docs/commands.md#exit-codes-and-interrupted-generation) before changing managed files.

## Develop locally

From the repository root:

```sh
dart pub get
dart analyze --fatal-infos
dart test
```

After editing `lib/src/cli/commands.json`, regenerate its bundled copy:

```sh
dart run tool/generate_commands.dart
```

For end-to-end verification against Flutter, supply an existing temporary parent directory:

```sh
dart run tool/verify_flutter.dart /absolute/path/to/temp-parent
```

This creates and retains disposable apps, runs code generation, analysis, and tests, and needs network access for uncached dependencies. Verification targets Flutter 3.50.0 and Dart 3.14.0 on macOS.

## Documentation

- [Command reference](docs/commands.md): options, defaults, JSON contracts, adoption, and failure behavior.
- [Architecture](docs/architecture.md): generated code, managed files, and CLI internals.
- [Changelog](CHANGELOG.md): release changes.
