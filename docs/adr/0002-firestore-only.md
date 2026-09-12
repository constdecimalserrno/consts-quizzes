# Firestore only, no Realtime Database

Firestore bills per document read, so broadcasting one Slot to N listeners
costs N reads every time it changes. Realtime Database bills download bytes
instead, which makes it roughly four times cheaper for this exact fan-out
shape. We chose Firestore alone anyway: one datastore, one security rules
language, one mental model, against a project with a hard $50/month budget and
a realistic load of a handful of Players.

## Consequences

Sustained concurrency is capped near 120 Players rather than ~600. The upgrade
path is contained: move the two hot paths — Slot broadcast and Answer writes —
to Realtime Database, leaving everything durable in Firestore. That is two
paths, not a rewrite. Do not "simplify" by adding a second datastore for
anything else.
