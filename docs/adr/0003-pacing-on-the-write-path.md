# Pacing is enforced when an Answer is written, not by withholding Questions

A Player must not be able to answer all of a Round's Slots at once. The obvious
approach is to withhold each Question until its Slot opens, and we do that. But
the guarantee does not come from concealment — concealment is defeated by any
client that reads its own network traffic, and this project permits cheating by
design. The guarantee comes from Firestore security rules rejecting any Answer
written outside its Slot's Window, and rejecting a second Answer for a Slot
already answered.

## Consequences

Each Player writes once per Slot — twenty writes per Round — and that cost is
not optional; it is what makes the Window real. Batching Answers into a single
write at the end of a Round would halve the bill and destroy the guarantee.

Elapsed time is still self-reported by the client, so speed points can be
farmed. Accepted: scores are capped by the Window the server enforces, and
cheating is a permitted category here.
