# Changelog

## Unreleased

- Add schema-4 managed apps with configured Dio and safe typed errors, app-level GetIt composition, Freezed and checked JSON generation, asset declarations, and working English gen-l10n inputs across all four state backends.
- Register routes and DI only in exact, Forge-rendered integration files. Refuse edited or missing files, collisions, duplicate routes, and symlinks before all writes. Legacy schemas 1–3 retain manual registration.
- Add explicit `init --scaffold` with an alternate entrypoint and strict existing-file refusal. Keep default init metadata-only. Managed `--no-pub` and dry runs report required generation commands without running processes.
- Report managed registration status, updated files, required commands, and code-generation status in JSON. Verify managed navigation and user-edit refusal with the native Flutter verifier.
- Preflight exact codegen configuration and reject redirected or linked localization, builder, source-root, and build-cache paths before writes or dependency resolution. Namespace Freezed model entities and private converters so business names cannot shadow annotation classes.
- Add project-level Cubit, Bloc, Riverpod, and Provider choices to create, init, and the terminal wizard. Features inherit the project default or accept an explicit override without changing project defaults.
- Persist state management in schema v3. Read schemas v1 and v2 as Cubit without migration. Include only the selected backend's dependencies and check overrides before feature writes.
- Generate Riverpod 3 Notifiers with route-local scope overrides and Provider ChangeNotifiers with route-owned disposal. Share clean domain/data templates and verify retries, stale results, programming errors, and pending work at disposal.
- Qualify notifier backend and UI imports so valid feature names such as `change` and `stream` do not collide with framework exports. Reserve `riverpod` as an app name only for the Riverpod backend, whose required transitive package uses that name.
- Add metadata-only `init` for existing Flutter apps, including a name-free interactive flow and structured dependency warnings. Init does not change existing source or run pub.
- Default new apps and metadata to the clean data/domain/presentation recipe. Keep counter generation as an explicit recipe and preserve schema v1 counter/Flutter-lint behavior without metadata rewrites.
- Add schema v2 recipe and lint-profile defaults, package imports, Very Good Analysis by default for new apps, and an explicit Flutter lint profile.
- Require Dart 3.14 for the CLI and generated code, and Flutter 3.50 for generated apps. Templates use concise constructors to satisfy the current Very Good Analysis rules.
- Generate typed feature-local failures, fake-backed tests, load/retry/disposal behavior, and constructor-injected datasources, repositories, use cases, and controllers. Starter id/title fields are explicit examples, not inferred API contracts.
- Derive manual text and JSON wiring from one feature artifact. Support validated static route overrides without changing existing routers or claiming route uniqueness.
- Verify the compiled CLI with iOS/Android scaffolds across four backends, two recipes, and both lint profiles. Analyze and test exact route wiring, cross-backend overrides, business-name collisions, legacy metadata, and metadata-only adoption with manual dependency commands.

## 0.1.0

- Add a line-based terminal wizard with CI detection, explicit interactive controls, validation retries, and confirmation before generation.
- Add `--json` with a versioned result schema, structured file lists and manual wiring, error details, and Flutter logs on stderr.
- Accept common flags before or after subcommands and cover terminal policy and subprocess output with hermetic tests.
- Add local-only `flutter-forge create` with platform selection, organization, output directory, dry-run, and optional dependency resolution.
- Add standalone Cubit and Bloc feature generation with manual route registration instructions.
- Generate a working counter app, controller tests, and route widget tests.
- Add path and collision checks, schema metadata, and staged failure reports without rollback.
- Add CLI tests and a repeatable compiled-CLI Flutter web verification script.

This version is unpublished. The command name is provisional.
