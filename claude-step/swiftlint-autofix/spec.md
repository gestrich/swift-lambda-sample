# SwiftLint Autofix

Fix SwiftLint violations using the swiftlint autofix command.

## Instructions

**IMPORTANT: Use Bash to run the swiftlint command. Do NOT manually edit the file.**

For each task:
1. Run the exact bash command shown in the task (e.g., `swiftlint lint --fix "Package.swift"`)
2. The swiftlint tool will automatically modify the file
3. Commit the changes made by swiftlint

**Do NOT:**
- Manually edit Swift files
- Make any changes beyond what swiftlint does
- Add or modify comments
- Change formatting beyond what swiftlint fixes

**Do:**
- Use the Bash tool to execute the swiftlint command
- Commit only the changes swiftlint makes

## Tasks

- [x] Run `swiftlint lint --fix "Package.swift"`
- [ ] Run `swiftlint lint --fix "Sources/apps/LambdaApp/Postgres/User.swift"`
- [ ] Run `swiftlint lint --fix "Sources/apps/LambdaApp/Postgres/PostgresModelStore.swift"`
- [ ] Run `swiftlint lint --fix "Sources/apps/LambdaApp/SwiftServerApp.swift"`
- [ ] Run `swiftlint lint --fix "Sources/apps/LambdaApp/Handlers/APIGatewayHandler.swift"`
- [ ] Run `swiftlint lint --fix "Sources/apps/MacApp/Models/DeployRemoteModel.swift"`
- [ ] Run `swiftlint lint --fix "Sources/apps/MacApp/UI/Client/UserFormView.swift"`
- [ ] Run `swiftlint lint --fix "Sources/apps/MacApp/UI/CLIUI/CommandInputView.swift"`
- [ ] Run `swiftlint lint --fix "Sources/apps/MacApp/UI/CLIUI/StreamingTextView.swift"`
- [ ] Run `swiftlint lint --fix "Sources/sdks/CLIMacrosSDK/Plugin.swift"`
- [ ] Run `swiftlint lint --fix "Sources/services/StorageService/ProjectPathResolver.swift"`
- [ ] Run `swiftlint lint --fix "Tests/DeployRemoteFeatureTests/LinuxDeployTests.swift"`
