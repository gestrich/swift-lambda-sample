# SwiftLint Autofix

Fix SwiftLint violations that have the autofix option available.

## Instructions

Run `swiftlint --fix --path "path/to/file.swift"` for each file listed below.

**Important:**
- It is NOT necessary to build after making these changes
- The autofix only modifies formatting/style issues
- Just run the fix command for the specified file

The following rules are auto-fixable:
- `trailing_comma` - Collection literals should not have trailing commas
- `trailing_whitespace` - Lines should not have trailing whitespace
- `vertical_whitespace` - Limit vertical whitespace to a single empty line

## Tasks

- [x] Run `swiftlint --fix --path "Package.swift"` to fix 23 trailing_comma violations
- [ ] Run `swiftlint --fix --path "Sources/apps/LambdaApp/Postgres/User.swift"` to fix 14 trailing_whitespace violations
- [ ] Run `swiftlint --fix --path "Sources/apps/LambdaApp/Postgres/PostgresModelStore.swift"` to fix trailing_whitespace and trailing_comma violations
- [ ] Run `swiftlint --fix --path "Sources/apps/LambdaApp/SwiftServerApp.swift"` to fix trailing_whitespace and vertical_whitespace violations
- [ ] Run `swiftlint --fix --path "Sources/apps/LambdaApp/Handlers/APIGatewayHandler.swift"` to fix 1 trailing_whitespace violation
- [ ] Run `swiftlint --fix --path "Sources/apps/MacApp/Models/DeployRemoteModel.swift"` to fix 2 trailing_whitespace violations
- [ ] Run `swiftlint --fix --path "Sources/apps/MacApp/UI/Client/UserFormView.swift"` to fix 1 trailing_whitespace violation
- [ ] Run `swiftlint --fix --path "Sources/apps/MacApp/UI/CLIUI/CommandInputView.swift"` to fix trailing_comma and vertical_whitespace violations
- [ ] Run `swiftlint --fix --path "Sources/apps/MacApp/UI/CLIUI/StreamingTextView.swift"` to fix 1 trailing_comma violation
- [ ] Run `swiftlint --fix --path "Sources/sdks/CLIMacrosSDK/Plugin.swift"` to fix 1 trailing_comma violation
- [ ] Run `swiftlint --fix --path "Sources/services/StorageService/ProjectPathResolver.swift"` to fix 2 trailing_whitespace violations
- [ ] Run `swiftlint --fix --path "Tests/DeployRemoteFeatureTests/LinuxDeployTests.swift"` to fix 1 vertical_whitespace violation
