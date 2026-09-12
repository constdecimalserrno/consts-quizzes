# The concurrency cap is what enforces the budget, not billing alerts

This project has a hard $50/month ceiling. Firebase budget alerts are
notifications, not caps, and billing data lags six to twenty-four hours, so a
spike can overshoot badly before any alert fires. Spend here is dominated by
per-Player-per-Slot reads and writes, which scale linearly with concurrent
Players. So the bound is applied to the input: `config/app.maxConcurrentPlayers`,
enforced by a transaction counter at join. Over the cap, a visitor is told the
Round is full and no listener is attached.

## Consequences

`maxConcurrentPlayers` is the dial that sets the bill; treat changing it as a
spending decision. Backstops, in order of how fast they act: `maxInstances` on
every function (instant), the concurrency cap (instant), a soft kill switch at
$40 that puts the game read-only (lagged), and detaching the billing account at
$50 (lagged, and it takes the project down rather than degrading it).
