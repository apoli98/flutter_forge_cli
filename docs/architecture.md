# Architecture and ownership

Flutter Forge keeps composition in the application and state behavior inside each feature. Generated files become application code after generation. There is no feature registry, service locator, code generation, networking layer, or localization setup.

## Generated application

`lib/main.dart` starts `App`. `lib/app/app.dart` creates and disposes the `GoRouter`, applies `theme.dart`, and builds `MaterialApp.router`. `lib/app/router.dart` owns the route list and supplies controller factories. Home uses the same route factory contract as later features.

Each `lib/features/<name>` directory contains a route factory and a `presentation` directory. The page renders state and dispatches the increment action. A Cubit exposes `increment()`. A Bloc handles its increment event. Both accept `initialCount` through their constructors and emit immutable value states.

The route factory takes a controller factory through a required parameter. Its `BlocProvider` creates and closes the controller. To add a repository later, inject the repository through the controller constructor and supply that dependency at the app's composition point. No global dependency container is generated.

Generated unit tests verify initial state and repeated increments. Generated route widget tests verify factory injection, visible counter updates, and provider-owned disposal. The app widget test verifies that Home opens and increments through the actual app router.

The handwritten router, pubspec, and dependency wiring remain yours. Feature generation writes only its new feature and test directories. It prints registration instructions rather than attempting to merge Dart source.

## CLI internals

`lib/src/cli/options.dart` defines the parser and resolved command options. Common flags are registered at both parser levels rather than moved between tokens. `runner.dart` chooses interactive or argument-only execution, orchestrates Flutter, and preserves the generation preflight.

`prompt.dart` collects omitted values through asynchronous line input. `PromptInput` injects terminal capability and input for tests. `runCli` also accepts the environment, output sinks, a working directory, and a `FlutterToolchain`. Injecting an output sink defaults terminal capability to false unless the caller supplies `PromptInput`, so tests do not inherit a developer's terminal.

`reporter.dart` owns the JSON envelope and human output policy. Operations fill structured data directly rather than capture human prose. The system toolchain sends its logs to stderr in JSON mode. Each handled execution path finishes one result.

`lib/src/project` validates identifiers and reads schema metadata. `lib/src/templates` contains bundled Dart strings, so templates also work in a compiled executable. `GenerationPlan` describes complete relative file contents and required-absent directories. `FileWriter` checks paths and collisions before writing. `SystemFlutterToolchain` locates Flutter and streams subprocess output.

The create flow validates the absent target, runs Flutter's platform generator, applies the limited fresh-scaffold overlay, and resolves dependencies. The feature flow checks metadata and collisions, writes new files, and prints manual wiring. Failure and interruption limits are in the [command reference](commands.md#exit-codes-and-interrupted-generation).
