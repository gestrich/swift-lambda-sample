# Documentation Workflow

This document describes how technical documentation is organized and managed in this project.

## Directory Structure

```
docs/
├── architecture/    # Stable architecture documentation
├── guides/          # How-to guides and tutorials
├── proposed/        # In-progress specs and proposals
└── completed/       # Finished implementation docs
```

## Proposed vs Completed

### `docs/proposed/`

Contains specifications and plans that are **in progress** or **under review**:

- Feature proposals
- Refactoring plans
- Architecture change requests
- Implementation specifications

Documents here represent work that is planned but not yet implemented, or implementations that are in progress.

### `docs/completed/`

Contains documentation for work that has been **finished and merged**:

- Completed refactoring summaries
- Implemented feature documentation
- Historical records of past changes

## Workflow

1. **Create a proposal** in `docs/proposed/` when planning new work
2. **Implement** the feature or refactor based on the proposal
3. **Move to completed** once the implementation is merged

```bash
# After implementation is complete
git mv docs/proposed/my-feature.md docs/completed/my-feature.md
```

## Architecture Documentation

The `docs/architecture/` folder contains stable, long-lived documentation:

- `layered-architecture.md` - Core architecture patterns
- `code-style.md` - Code conventions and style guide
- `PRINCIPLES.md` - Design principles

These documents are updated in place as the architecture evolves, rather than following the proposed/completed workflow.
