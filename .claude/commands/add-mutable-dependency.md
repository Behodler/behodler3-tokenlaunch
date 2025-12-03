# Add Mutable Dependency

Adds a sibling submodule as a mutable dependency, exposing only interfaces.

## Usage

```
/add-mutable-dependency <repository>
```

## Arguments

- `repository` (required): The repository URL or path for the mutable dependency

## Description

This command clones a sibling submodule into `lib/mutable/` and removes all implementation details, keeping only the `src/interfaces/` directory. This ensures that mutable dependencies only expose interfaces and abstract contracts, never implementation details.

## Workflow

1. Clones the repository to `lib/mutable/<repo-name>`
2. Validates that an `src/interfaces/` directory exists
3. Removes all content except interfaces
4. Reports success or failure

## Example

```
/add-mutable-dependency ../vault
```

---

Run the script:

```bash
.claude/scripts/add-mutable-dependency.sh $ARGUMENTS
```
