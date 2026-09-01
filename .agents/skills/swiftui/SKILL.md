---
name: swiftui-development
description: >-
  Use this skill when designing, building, refactoring, or troubleshooting SwiftUI views, components,
  and state management within the AMT macOS application.
---

# SwiftUI Development Skill

This skill contains instructions and workflows for developing SwiftUI views and managing view states within the AMT application.

## Key SwiftUI Patterns in AMT

### 1. State Management
- Use `@State` only for simple, view-local properties (e.g. toggle state, text field inputs).
- Use `@Binding` for read-write properties owned by a parent view.
- For business logic and data fetching, use observable classes conforming to `ObservableObject` with `@StateObject` (instantiated in the view) or `@ObservedObject` (passed into the view).
- Ensure that heavy tasks (such as ML inference in `QwenSuggestionService`) are executed asynchronously using Swift Concurrency (`Task`, `async/await`) to keep the main/UI thread responsive.

### 2. UI Aesthetics and Structure
- Build clean, premium layouts using semantic, flexible stacks (`VStack`, `HStack`, `ZStack`).
- Make sure components use the correct design system colors (e.g., Primary/PrimaryMain, Status/Error/StatusErrorDark, etc.) from `Assets.xcassets`.
- Implement smooth transitions and micro-animations where appropriate, using SwiftUI's `.animation(.easeInOut, value: ...)` or `.withAnimation { ... }`.
- Follow HIG (Human Interface Guidelines) for macOS applications.

## Development Workflow

### Step 1: Draft the SwiftUI Component
Create or modify the SwiftUI view. Keep it modular and break complex views into smaller subviews.

### Step 2: Implement Preview Helpers
Always provide a `#Preview` block at the bottom of the SwiftUI file containing mock data or stubbed instances of services (e.g., `LegalDictionaryStore.preview` or custom mocks) so it can be previewed in Xcode Canvas.

### Step 3: Validate and Build
Run the build command to ensure the compiler does not raise any syntax errors:
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
Refer to the build rules in [.agents/rules/swiftui_build.md](../../rules/swiftui_build.md) for more testing and benchmark commands.
