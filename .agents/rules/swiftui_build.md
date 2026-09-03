# SwiftUI Build Rules & Guidelines

This rule provides instructions and commands for building, testing, and developing the SwiftUI-based AMT (Lawtionary) macOS application.

## Build Commands

Always use the following command to build the application from the command line without requiring code signing:

```bash
xcodebuild \
  -project AMT.xcodeproj \
  -scheme AMT \
  -configuration Debug \
  -sdk macosx \
  -arch arm64 \
  -derivedDataPath /tmp/amt-build-debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

For Release builds, use:
```bash
xcodebuild \
  -project AMT.xcodeproj \
  -scheme AMT \
  -configuration Release \
  -sdk macosx \
  -arch arm64 \
  -derivedDataPath /tmp/amt-build-release \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Testing Commands

To run unit tests deterministically without downloading or using LLM models:

```bash
xcodebuild \
  -project AMT.xcodeproj \
  -scheme AMT \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/amt-tests \
  CODE_SIGNING_ALLOWED=NO \
  test
```

To run the model evaluation benchmarks (requires network to download Legal 4B model):

```bash
TEST_RUNNER_AMT_RUN_P09_MODEL_BENCHMARK=1 \
TEST_RUNNER_AMT_P09_REPORT_PATH=/private/tmp/amt-p09-legal-4b.json \
xcodebuild \
  -project AMT.xcodeproj \
  -scheme AMT \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/AMT-P09-DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:AMTTests/AIConnectorModelBenchmarkTests \
  test
```

## SwiftUI Development Guidelines

1. **State Management**:
   - Use SwiftUI standard state wrappers appropriately: `@State` for local private state, `@Binding` for passing mutable state down, and `@StateObject` / `@ObservedObject` or modern Observation frameworks for view models (`QwenSuggestionService`, `LegalDictionaryStore`, etc.).
   - Explicitly inject environment or dependency objects from `AMTApp` downwards rather than using singletons where possible.

2. **UI & Code Style**:
   - Use clean, modular layouts separated into logical features (e.g. Dashboard, Dictionary, AIConnector, Suggestion).
   - Verify code with `git diff --check` to check for whitespace issues.
   - Do not commit changes to Hugging Face model cache or build artifacts (ensure they remain in `/tmp` or `/private/tmp`).
