# Profile Management

Profiles store a required first name and an optional last name. Both fields trim
surrounding whitespace. `Dependent#name` joins the fields for existing display,
calendar, document, and question-answering callers. A one-name profile remains
valid, and either field can contain multiple words.

The creation form includes name fields, optional photo, date of birth, and
notes. Grade and school are available on the edit form; creation requests do
not accept them. Date of birth remains optional. User sign-up names are not
part of this change.

The edit page exposes Delete profile with a confirmation explaining that its
appointments, saved questions, and care team memberships are also removed.
Profiles with documents cannot be deleted: the existing model restriction
remains, and the page links to those documents with instructions to remove
them first. Requests scope the profile to the signed-in user's current account.
Document reassignment and wrong-person detection remain outside this scope.

## Existing Name Backfill

The schema migration only renames the original name column to `legacy_name`,
makes that legacy column nullable for new profiles, adds nullable first/last
columns, and replaces the account/name index. Data changes run separately:

```bash
bin/rails db:migrate
bin/rails runner scripts/backfill_profile_names.rb
```

Pause requests and drain/stop workers before deploying this schema change:
older running code still reads the renamed `name` column. Run both commands
with the intended Rails environment, then restart the web and worker processes
on the new code before reopening requests. Existing names can still display
from `legacy_name` while the backfill is pending, but profile validation requires
a first name.

The script splits the original name at the first whitespace boundary, retaining
the remainder as the last name and keeping the original full text. Families
can correct the split afterward. It only fills rows whose first and last names
are both null, checks that condition again on write, and leaves already entered
names alone. A second run is safe. Blank or partially populated legacy records
are reported as unresolved, with a nonzero exit status so an operator can
correct them rather than assume completion. Original names are not printed.

Before rolling back this schema, first copy current names (including newly
created profiles and later corrections) into the legacy column:

```bash
bin/rails runner scripts/backfill_profile_names.rb restore
bin/rails db:migrate:down VERSION=20260904000100
```

Run both rollback steps with requests paused. The migration itself contains no
data backfill in either direction.

## Validation

```bash
ruby scripts/paper_bridge_harness.rb foundation
ruby scripts/paper_bridge_qa_harness.rb workflow profiles
ruby scripts/paper_bridge_qa_harness.rb workflow onboarding
```

The focused Rails checks cover backfill reruns, manual-review failures, rollback
preparation, names, form parameters, account isolation, and deletion behavior.
Browser checks cover create/edit, cancellation and confirmation of deletion,
document-backed deletion refusal, and the first-run tour with split name fields.
