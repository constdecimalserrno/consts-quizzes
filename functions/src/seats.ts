import { FieldValue, type Firestore } from 'firebase-admin/firestore'

/**
 * Seats: the hard cap on how many Players a Round carries.
 *
 * Every guard in this project except this one is lagging. Budget alerts arrive
 * a day after the spend, and by then a runaway has already happened. Spend
 * scales with the number of Players attached to a Round, so the number of
 * Players attached to a Round is what gets bounded, at the moment they try to
 * join, in a transaction that cannot admit more than the cap however many
 * arrive at once.
 *
 * A visitor refused a seat still sees the broadcast — they simply are not
 * counted, do not answer, and cost a single document read rather than a
 * listener for the length of a Round.
 */
export const seatDoc = (roundId: string) => `rounds/${roundId}/meta/seats`

export type SeatResult =
  | { seated: true; taken: number }
  | { seated: false; reason: 'full' | 'closed'; taken: number }

export async function takeSeat(
  db: Firestore,
  roundId: string,
  uid: string,
  cap: number,
  open: boolean,
): Promise<SeatResult> {
  if (!open) return { seated: false, reason: 'closed', taken: 0 }

  const seats = db.doc(seatDoc(roundId))
  const held = db.doc(`rounds/${roundId}/seatHolders/${uid}`)

  return db.runTransaction(async (tx) => {
    const [seatsSnap, heldSnap] = await Promise.all([tx.get(seats), tx.get(held)])
    const taken = (seatsSnap.data()?.taken as number) ?? 0

    // Already seated: re-joining from a second tab or after a reconnect must
    // not consume a second seat, or a refresh would slowly fill the Round.
    if (heldSnap.exists) return { seated: true, taken }

    if (taken >= cap) return { seated: false, reason: 'full' as const, taken }

    tx.set(held, { at: FieldValue.serverTimestamp() })
    tx.set(seats, { taken: FieldValue.increment(1) }, { merge: true })
    return { seated: true, taken: taken + 1 }
  })
}
