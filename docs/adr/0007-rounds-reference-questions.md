# A Round references Questions, but the live Slot carries a copy

Everything in the data model is by reference: a Round holds Question references,
not Question content. Followed literally on the read path this costs two reads
per Player per Slot — one for the live document, one for the Question it points
at — which halves the concurrency the budget allows.

The Tick therefore denormalises the opening Question's prompt and Choices into
the live document. References remain the source of truth; the live document is
a write-once projection of the currently open Slot.

## Consequences

One read per Player per Slot. The copy is never edited after the Slot opens,
and the correct Choice is never written into it.
