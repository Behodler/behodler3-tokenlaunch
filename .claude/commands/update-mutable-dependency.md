# Update Mutable Dependency

Updates an existing mutable dependency to pull the latest interface changes.

## Usage

```
/update-mutable-dependency <dependency-name>
```

## Arguments

- `dependency-name` (required): The name of the mutable dependency to update (directory name in `lib/mutable/`)

## Description

This command updates an existing mutable dependency by pulling the latest changes from its remote repository, then cleaning up to keep only interfaces. Use this after a sibling submodule has implemented requested changes.

## Workflow

1. Reverts any local changes to restore all files
2. Pulls latest changes from the remote
3. Validates that an `src/interfaces/` directory exists
4. Removes all content except interfaces
5. Reports success or failure

## Example

```
/update-mutable-dependency vault
```

---

Run the script:

```bash
.claude/scripts/update-mutable-dependency.sh $ARGUMENTS
```
