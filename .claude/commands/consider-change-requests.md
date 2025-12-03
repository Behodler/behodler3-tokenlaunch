# Consider Change Requests

Reviews and processes incoming change requests from sibling submodules.

## Usage

```
/consider-change-requests
```

## Arguments

None

## Description

This command displays the contents of `SiblingChangeRequests.json`, which contains change requests that other sibling submodules have made against this submodule's interfaces. After reviewing, implement the requested changes using TDD principles.

## Workflow

1. Checks for the existence of `SiblingChangeRequests.json`
2. Displays the contents of the change requests
3. Prompts to implement changes using TDD principles
4. If a request cannot be implemented, document the issue for the requesting submodule

## Example

```
/consider-change-requests
```

---

Run the script:

```bash
.claude/scripts/consider-change-requests.sh
```
