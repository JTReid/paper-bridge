# Care Team Access Runbook

This runbook protects the currently implemented account, dependent, and care
team access shape.

## Contract

- `User` is the single login identity for family account members and invited
  care team members.
- `Account` is the tenant boundary.
- Family account users join accounts through `AccountMembership` records with
  `admin` or `member` roles.
- Dependents belong to one account and scope documents plus care team access.
- `CareTeamMembership` links one user to one dependent.
- Care team memberships store role, invite status, inviter, invite timestamps,
  and category permissions.
- Care team invitations create a login user when the email does not already
  exist.
- Inviting an existing user does not overwrite the user's identity.
- Care team invite creation does not add an `AccountMembership`.
- Only account managers can invite care team members for an account dependent.
- Care team category permissions normalize checkbox/string/symbol inputs into
  deterministic booleans.
- Search authorization maps account roles or care team category permissions to
  allowed document chunk labels through `Documents::SearchAccessProfile`.

## Validation

```bash
ruby scripts/paper_bridge_harness.rb foundation
ruby scripts/paper_bridge_harness.rb access
```
