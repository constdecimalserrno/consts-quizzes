# Cloud Tasks drives the Tick, not Cloud Scheduler

Slots are roughly fifteen seconds long. Cloud Scheduler cannot fire faster than
once a minute, so it cannot drive this game. The alternative — one long-lived
function per Round that sleeps between Slots — bills wall-clock vCPU-seconds
and would cost more than everything else in the project combined, while a
single crash would take out a whole Round. We use self-rescheduling Cloud Tasks:
each Tick enqueues the next at an exact timestamp.

## Consequences

About forty tasks per Round, comfortably inside the free tier. A dropped task
costs one Slot rather than the Round. Cloud Tasks is scheduling infrastructure,
not a second datastore, so it does not contradict ADR-0002.
