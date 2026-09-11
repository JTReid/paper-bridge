# Care Team Contacts Runbook

Care Team stores contacts for a profile. Account authentication and document
access remain separate from these contact records.

## Contract

- `Account` is the tenant boundary. Family users join accounts through
  `AccountMembership` records with `admin` or `member` roles.
- `Dependent` scopes the profile's documents and care team contacts.
- `CareTeamMembership` retains its existing class name and routes but stores a
  contact: required name, role, and email, plus optional `phone_number`.
- Email addresses are normalized and must be unique within the profile. The
  same contact email may be saved on another profile.
- Account managers can add, edit, and remove contacts in their account. Records
  cannot be managed through another account's profile.
- `invited_by` records the creating user for provenance; it does not represent
  an invitation workflow.
- Saving a contact does not create or update a `User`, create an
  `AccountMembership`, send an invitation email, or require the contact to sign
  up. Contact details can match an existing login without changing it.
- Contact roles describe the person's relationship to the profile. They do not
  grant access to documents or Ask PaperBridge.
- The add and edit forms contain Name, Role, Email, and Phone number. Care Team
  cards show contact details without access status or category permissions.
- Document sharing offers saved contact names and email addresses in its
  recipient picker. The family chooses which documents to send as attachments.
- Existing login links, invitation status, timestamps, and permissions remain
  in storage for compatibility but are unused by the contact workflow and
  search authorization. Existing login records are not deleted.
- `Documents::SearchAccessProfile` checks membership in the requested account.
  Contact records and legacy care team permissions grant no search access.

## Validation

The existing `access` selector covers contact persistence and account-based
search access:

```bash
ruby scripts/paper_bridge_harness.rb access
ruby scripts/paper_bridge_qa_harness.rb workflow care-team
ruby scripts/paper_bridge_qa_harness.rb negative care-team
```
