/// Git CLI program definition using macro-based API
@CLIProgram
public struct Git {
    /// Git merge command
    /// Example: git merge --no-ff -m "Merge feature" feature-branch
    @CLICommand
    public struct Merge {
        /// Use --no-fast-forward merge strategy
        @Flag public var noFastForward: Bool = false

        /// Commit message for the merge
        @ShortOption("-m") public var message: String?

        /// Branch to merge
        @Positional public var branch: String
    }
}
