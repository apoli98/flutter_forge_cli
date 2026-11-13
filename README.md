# Flutter Forge CLI

Flutter Forge creates a feature-first Flutter app and adds standalone Cubit or Bloc counter features. The provisional command is `flutter-forge`. Version 0.1.0 is local-only and unpublished.

## Create an app

Use Flutter on your `PATH`. The CLI requires Dart 3.10 or newer. Generated apps require Dart 3.13 and Flutter 3.47 or newer. Verification uses Flutter 3.50.0 and Dart 3.14.0 on macOS.

From this repository:

```sh
dart pub get
dart run bin/flutter_forge.dart create demo --platforms web
cd demo
flutter run -d chrome
```

The Home page displays `Count: 0`. Press **Increment** to display `Count: 1`.

To install the command from the local checkout:

```sh
dart pub global activate --source path .
flutter-forge --help
flutter-forge create my_app --platforms web
```

Add Dart's global executable directory to `PATH` if needed. No package has been published, so `dart pub global activate flutter_forge_cli` is not an installation option.

## Use the terminal wizard

```sh
flutter-forge
flutter-forge create
flutter-forge feature --state bloc
flutter-forge create my_app --interactive --platforms web
```

With terminal input and output, the first command offers a numbered create-or-feature choice. A command without a name starts its wizard unless `CI` is set. The wizard asks only for omitted values, shows the resolved command, and requires confirmation. Press Enter to accept a displayed default. The confirmation defaults to **no**.

Commands that include a name never prompt unless you pass `--interactive`. Use `--no-interactive` to prohibit prompts, including in a terminal. See the [interactive behavior reference](docs/commands.md#interactive-behavior) for CI rules and cancellation.

## Use from an agent or script

```sh
flutter-forge --json create my_app --platforms web --dry-run
flutter-forge create my_app --platforms web --no-pub --json
flutter-forge --json feature orders --project-dir /absolute/path/to/my_app --state bloc
```

`--json` never prompts. It writes exactly one JSON object to stdout, including on errors. Read `success`, `exitCode`, and the structured `data` fields. Flutter logs go to stderr. Feature results include `registered: false` and separate wiring fields. The [JSON schema reference](docs/commands.md#json-output) lists the fields and failure details.

## Generate a feature

From the generated project:

```sh
flutter-forge feature order_history
flutter-forge feature activity --state bloc
```

Without global activation, run the CLI from its checkout and pass the app directory:

```sh
dart run bin/flutter_forge.dart feature order_history --project-dir /absolute/path/to/demo
```

The command prints `Generated, not registered` and exact instructions. For `order_history`, add these imports to `lib/app/router.dart`:

```dart
import '../features/order_history/order_history_route.dart';
import '../features/order_history/presentation/order_history_cubit.dart';
```

Add this entry to the existing `GoRouter` routes list:

```dart
orderHistoryRoute(createOrderHistoryCubit: OrderHistoryCubit.new),
```

Navigate with `context.go('/order_history')` from a widget that imports `package:go_router/go_router.dart`. The CLI does not add navigation buttons.

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

The Flutter verification script creates a unique directory under the supplied parent and retains the artifacts. It compiles the CLI, creates a web app, generates both feature variants, applies the printed route snippets, and runs Flutter analysis, widget tests, and a web build. It needs network access for uncached packages. On this development machine, the approved temporary parent is `/private/var/folders/f7/wgd6hcg910383s9x8pbnzq200000gp/T/opencode`.
