# Add Immutable Dependency

Adds an external library as an immutable dependency with full source code access.

## Usage

```
/add-immutable-dependency <repository>
```

## Arguments

- `repository` (required): The repository URL or path for the immutable dependency

## Description

This command clones an external library (such as OpenZeppelin) into `lib/immutable/` with full source code access. Unlike mutable dependencies, immutable dependencies retain all their implementation details.

## Workflow

1. Clones the repository to `lib/immutable/<repo-name>`
2. Reports success

## Example

```
/add-immutable-dependency https://github.com/OpenZeppelin/openzeppelin-contracts
```

---

Run the script:

```bash
.claude/scripts/add-immutable-dependency.sh $ARGUMENTS
```
