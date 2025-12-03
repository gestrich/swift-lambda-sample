// Re-export CLIService from CLIKit so consumers don't need to import CLIKit directly.
// This avoids macro conflicts between CLIKit's @Option/@Flag and ArgumentParser's @Option/@Flag.
@_exported import class CLIKit.CLIService
