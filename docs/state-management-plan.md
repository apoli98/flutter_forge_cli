# State management implementation

## Progress

- [x] Ground CLI resolution, metadata, generation, and wiring.
- [x] Compare available architecture options and select a design.
- [x] Reconcile the implementation contract (no human checkpoint requested).
- [x] Implement and verify each unit.
- [x] Review the result; replace the design if implementation exposes structural problems.

## Scope

Support Cubit, Bloc, Riverpod, and Provider during app creation and adoption.
Persist the selected project default and inherit it during feature generation,
with an explicit per-feature override. Preserve existing schema 1 and 2 behavior
without rewriting metadata. Keep fpdart clean data/domain code independent of
presentation. Generate working app wiring and behavioral tests for each choice.

## Design comparison rubric

1. Existing project and command compatibility.
2. Idiomatic generated presentation code and lifecycle ownership.
3. One source of truth for state selection, dependencies, and wiring.
4. Small interfaces without a template framework or duplicated domain code.
5. Verification through generated apps, not only template string assertions.

## Verified package constraints

The pub.dev API currently reports `flutter_riverpod ^3.5.0` and
`provider ^6.1.5+1` as stable versions. Riverpod 3 lifecycle and scoping must be
checked against the real package during generated-app verification.

## Grounding

The earlier candidate files `state-design-a.md` and `state-design-b.md` were not
present in the supplied temporary directory when implementation resumed. The
chosen design keeps `StateStyle` in project profiles, uses one conditional
dependency inventory, and gives notifier backends their own small presentation
templates. Clean domain/data templates and state declarations are shared. A
generic emitter framework was rejected because it would hide native APIs and
add indirection to four fixed choices. Route factories own controller lifetimes;
Riverpod uses an auto-disposed provider overridden in a route-local scope.

`collectOptions` resolves terminal input and flags before `runner.dart` invokes
generation. `ProjectConfig` owns strict schema validation. `dependenciesFor` and
`devDependenciesFor` feed generated pubspecs, app-name validation, and adoption
checks, so state-specific dependency policy belongs there rather than in CLI
branches. `appPlan` composes Home through the same `featureArtifact` used for
standalone features. `FeatureWiring` derives human and JSON registration from one
contract; its current Bloc ownership text must become backend-specific.

Clean domain and data files live in `clean_feature_templates.dart` beside
presentation files. Shared domain/data helpers serve both presentation emitters.
Backend dispatch distinguishes Cubit/Bloc from Riverpod/Provider before the
backend-specific branches run.
Feature creation must continue writing only new feature/test directories, never
the consumer's router, pubspec, or existing metadata. Init remains metadata-only.

Baseline: `dart test` passed all 82 tests before implementation. Completion adds
CLI coverage for each backend, schema compatibility, exact dependency-name
validation, inherited wizard defaults, and cross-backend dependency preflight.

## Verification contract

- CLI tests cover all four selections for create/init/feature, inherited defaults,
  explicit overrides, invalid selections, wizard confirmation, and JSON output.
- Schema tests cover historical versions, strict invalid-field rejection, and
  round trips for every new persisted state choice without migration writes.
- Dependency tests prove that Riverpod/Provider apps do not require Bloc packages,
  and that overrides check the feature's actual requirements before any writes.
- Generated Flutter apps exercise both recipes and lint profiles. Clean tests
  retain typed failures, programming-error propagation, retry, disposal, and
  latest-request-wins behavior. Counter tests exercise updates and ownership.
- Real route wiring is consumed verbatim in a disposable app, including a
  cross-backend feature, then analyzed and tested.
- The matrix creates 16 iOS/Android scaffolds: four states, two recipes, and two
  lint profiles. Each app also generates order/either/option/task/provider/notifier/change/stream
  features and consumes same-backend and cross-backend registration. It does
  not build or launch native binaries.
- Keep verification focused on app scaffolding and Flutter tests. No website or
  browser-based stack builder is part of this implementation.

## Execution constraints

Earlier model-routing failures no longer block implementation. Completion runs
in the assigned implementation session without spawning more agents. Existing
uncommitted project work must be preserved throughout. Do not revert or commit.

## Completion verification

- `dart format --output=none --set-exit-if-changed bin lib test tool` passes.
- `dart analyze --fatal-infos` reports no issues. `dart test` passes 113 tests.
- `tool/verify_flutter.dart` passes with the final generated sources. All 16
  matrix apps pass Flutter analysis and tests before and after feature/wiring
  integration. Schema v1, schema v2, and adopted Provider apps also pass.
- After review corrections, all 35 Flutter analysis/test invocations pass,
  totaling 853 successful test executions, including change/stream regressions.
- Generated notifier route tests start pending work, navigate away, observe
  disposal, complete pending work without notifications/errors, and re-enter
  with fresh state. Riverpod uses its public `ProviderObserver` API.
- Artifacts: `forge_verify_UAgOsP` under the approved temporary parent. Full log:
  `state-review-matrix.log` beside it. No native device builds or web work ran.
- Independent code-reviewer recheck accepted by the parent. Both concrete
  findings are resolved, with no remaining concrete bugs. The reviewer also
  analyzed 76 exact generated files against real dependencies with no
  diagnostics and passed five targeted tests.

## Independent review corrections

The reviewer found that Provider feature `change` shadowed the framework's
`ChangeNotifier`, and Riverpod feature `stream` collided with its exported
`StreamNotifier`. Notifier templates now prefix backend imports and UI imports,
including route/page tests, instead of rejecting valid feature names. The real
app matrix keeps both names as regressions across both recipes and lint profiles.

The reviewer also found that an app named `riverpod` cannot satisfy the exact
transitive `riverpod` version required by `flutter_riverpod`. Selected-backend
app validation now reserves that name for Riverpod only, without adding a direct
dependency. Create, wizard final validation, init, and feature overrides all use
that same validation. CLI regressions prove rejection before writes/processes,
wizard retries, and acceptance for other backends.

The first three added regression tests failed before the fix. After the fix,
`dart analyze --fatal-infos` is clean and all 113 CLI tests pass. The updated
full Flutter matrix passes. The parent accepted the independent
code-reviewer recheck after both findings were resolved.
