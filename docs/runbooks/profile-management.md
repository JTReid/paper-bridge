# Profile Management

Profiles require both first and last name when created or edited. Both fields trim
surrounding whitespace. `Dependent#name` joins the fields for existing display,
calendar, document, and question-answering callers. Either field can contain
multiple words. Existing profiles without a last name need one entered before
edits can be saved; this change does not rewrite existing names.

Creation and editing use the same fields: first and last name, optional photo,
date of birth, and notes. Date of birth remains optional. Neither form exposes
grade or school, and creation/update requests do not accept those fields.
Previously saved grade and school values remain stored and displayed on profile
pages. User sign-up names are not part of this change.

The edit page exposes Delete profile with a confirmation explaining that its
appointments, saved questions, saved answers, meeting preparations, and care
team contacts are also removed.
Profiles with documents cannot be deleted: the existing model restriction
remains, and the page links to those documents with instructions to remove
them first. Requests scope the profile to the signed-in user's current account.
Document reassignment and wrong-person detection remain outside this scope.

## Validation

```bash
ruby scripts/paper_bridge_harness.rb foundation
ruby scripts/paper_bridge_qa_harness.rb workflow profiles
ruby scripts/paper_bridge_qa_harness.rb workflow onboarding
```

The focused Rails checks cover names, form parameters, account isolation, and deletion behavior.
Browser checks cover create/edit, cancellation and confirmation of deletion,
document-backed deletion refusal, and the first-run tour with split name fields.
