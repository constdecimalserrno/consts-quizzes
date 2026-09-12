/**
 * The budget watcher.
 *
 * Google's budget alerts are notifications, not caps — nothing stops spending
 * on its own — and the data behind them lags six to twenty-four hours. So this
 * is deliberately the *slow* half of the defence. The fast half is the seat
 * cap in `seats.ts`, which bounds the input in real time; this exists to say
 * that the model was wrong.
 *
 * Two thresholds. The soft one flips `killSwitch` and the game goes read-only
 * with a screen that explains itself. The hard one detaches billing, which
 * stops spend absolutely and takes the project down with it — a last resort,
 * not a control.
 */
export type BudgetNotification = {
  costAmount?: number
  budgetAmount?: number
  alertThresholdExceeded?: number
}

export const SOFT_FRACTION = 0.8
export const HARD_FRACTION = 1.0

export type BudgetVerdict = 'ok' | 'soft' | 'hard'

export function verdict(msg: BudgetNotification): BudgetVerdict {
  const spent = msg.costAmount
  const budget = msg.budgetAmount
  // Without both numbers there is nothing to judge, and guessing in the
  // direction of "shut it down" would make a malformed message an outage.
  if (typeof spent !== 'number' || typeof budget !== 'number' || budget <= 0) {
    return 'ok'
  }
  const fraction = spent / budget
  if (fraction >= HARD_FRACTION) return 'hard'
  if (fraction >= SOFT_FRACTION) return 'soft'
  return 'ok'
}
