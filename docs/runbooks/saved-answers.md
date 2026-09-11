# Saved Answers And Meeting Preparation

Families can keep completed Ask PaperBridge answers in a private research
library and arrange those answers into named meeting preparations. This is a
saved copy of existing work; saving, reading, searching, and organizing it do
not run AI again.

## Saved Answers

- `AiAssistantQuery` continues to own question execution, drafts, and the final
  AI response. Saving a completed answer creates a separate `SavedAnswer` with
  its question, answer, citations, and limitations copied into a snapshot.
  Saving the same query again reuses that snapshot; each query has at most one.
- The snapshot records when the answer was generated separately from when it
  was saved. Asking another question, reloading, or removing the original query
  does not replace the saved answer. Removing a query nullifies the origin link.
- A user can edit the saved title and their own notes. The original question,
  answer, sources, and limitations remain unchanged.
- Saved answers belong to one user, account, and profile. Another user in the
  same account does not receive access to that user's saved research.
- The library at `/profiles/:dependent_id/saved-answers` supports a
  case-insensitive, literal text search across title, question, answer text,
  notes, and source titles, plus a meeting filter. Characters such as `%` and
  `_` are ordinary search text, not wildcard operators.
- Source links use the existing authenticated document routes. If the original
  document is removed, the saved answer retains its source label and snapshot
  and marks that original as unavailable.

## Meeting Preparation

- `MeetingPrep` is a named collection owned by the same user, account, and
  profile as its saved answers. It does not create a calendar appointment.
- `MeetingPrepAnswer` joins a saved answer to a meeting preparation and records
  its position. One saved answer can appear in multiple meetings; adding it
  twice to one meeting does not duplicate it.
- A searchable checklist lets users select several saved answers and add them
  to a meeting together. Selections stay checked while searching other terms.
  Pressing Enter in the live search does not submit the selection; Add answers
  submits the batch. Already-added answers do not appear in the checklist.
- The checklist shows roughly five or six typical answers on desktop, with
  one-line answer previews and full, wrapping titles. Its height adapts to the
  viewport on smaller screens. Search and Add answers stay outside the scrolling
  list so they remain available while browsing choices.
- Users can remove answers and move them up or down. Adding, removing, and
  reordering update the meeting in place, preserving the meeting and checklist
  searches, remaining selections, open answers and sources, and the user's
  place on the page. Removing an answer from a meeting or deleting the meeting
  keeps the saved answer in the library.
- The meeting page loads all its saved answers in the chosen order. Its search
  filters that loaded content locally across the same text fields as the
  library. Filtering makes no request and changes no stored order; Clear
  restores the whole ordered meeting.
- Shared **Ask**, **Saved answers**, and **Meeting prep** navigation
  keeps all three pages in the current profile.
- Move to top/bottom controls are deferred. Printing and PDF export are outside
  this feature's scope.

## Validation

```bash
ruby scripts/paper_bridge_harness.rb saved-answers
ruby scripts/paper_bridge_qa_harness.rb workflow saved-answers
```

The Rails group covers snapshots, origin uniqueness, ownership, search, source
availability and preloading, single and batch meeting membership, ordering,
and deletion boundaries. The browser group
uses a dedicated synthetic profile and completed fake query results, including
a 30-answer meeting. It exercises saving from Ask PaperBridge, editing titles
and notes, searching, meeting reuse and order, batch selection across searches
without submitting on Enter, local filtering, state preservation after meeting
changes, and desktop and phone
picker layouts, including short screens, single-line previews, and independent
list scrolling. It does not run a worker or call a live model. Its setup and
cleanup only touch the scenario's synthetic profile.
