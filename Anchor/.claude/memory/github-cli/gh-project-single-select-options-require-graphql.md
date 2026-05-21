# Use GraphQL mutation to modify Project V2 single-select field options

**Category:** github-cli
**Severity:** high
**First seen:** 2026-05-21 (Issue #6 — Create GitHub Project v2 board + link repo)
**Last reinforced:** 2026-05-21

## Symptom
`gh project field-update` exits without error but silently does nothing when you attempt to add, remove, or rename options on a single-select field (e.g., the Status field). The field's option list remains unchanged.

## Root cause
The `gh project field-update` subcommand only supports updating a field's *value on an item* — not the field's *schema* (its option list). The GitHub Projects V2 API exposes option mutation exclusively through the `updateProjectV2Field` GraphQL mutation, which the CLI does not wrap.

## Fix
Use `gh api graphql` directly with the `updateProjectV2Field` mutation. Provide the field node ID and the full replacement option array (name + color + description per option). The mutation replaces the entire option list atomically, so include all options you want to keep.

```bash
# 1. Get the field node ID
FIELD_ID=$(gh api graphql -f query='
  query($login: String!, $number: Int!) {
    user(login: $login) {
      projectV2(number: $number) {
        fields(first: 20) {
          nodes { ... on ProjectV2SingleSelectField { id name } }
        }
      }
    }
  }' -f login=jonathangebru -F number=1 \
  --jq '.data.user.projectV2.fields.nodes[] | select(.name=="Status") | .id')

# 2. Replace the option list (example: 6-state workflow)
gh api graphql -f query='
  mutation($fieldId: ID!, $options: [ProjectV2SingleSelectFieldOptionInput!]!) {
    updateProjectV2Field(input: {fieldId: $fieldId, singleSelectOptions: $options}) {
      projectV2Field { ... on ProjectV2SingleSelectField { id name options { name } } }
    }
  }' \
  -f fieldId="$FIELD_ID" \
  -f options='[
    {"name":"Backlog",    "color":"GRAY",   "description":""},
    {"name":"Ready",      "color":"BLUE",   "description":""},
    {"name":"In Progress","color":"YELLOW", "description":""},
    {"name":"Review",     "color":"ORANGE", "description":""},
    {"name":"Done",       "color":"GREEN",  "description":""},
    {"name":"Awaiting You","color":"RED",   "description":""}
  ]'
```

## How to detect it next time
Before any task that modifies Project V2 field options, check: is the operation on an *item's value* or on the *field's schema*? If schema, reach for `gh api graphql` with `updateProjectV2Field`. Add this check to any automation script as a comment: `# gh project field-update cannot mutate single-select options — use GraphQL`.

## Related
- Issue: https://github.com/jonathangebru/vakter/issues/6
- Project: https://github.com/users/jonathangebru/projects/1
