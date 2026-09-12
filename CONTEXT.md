# const's quizzes

A single global trivia broadcast that never stops. One worldwide game runs at
all times; anyone can visit and join it mid-flight, signed in or not.

## Language

### The game

**Round**:
One complete broadcast game: a fixed number of slots followed by an
intermission. There is exactly one live Round at any moment, globally.
_Avoid_: game, match, session

**Slot**:
A numbered position within a Round, holding one Question and the window during
which answers for it are accepted.
_Avoid_: turn, step, index

**Window**:
The interval between a Slot's `opensAt` and `closesAt`, during which an Answer
may be written. Outside it, writes are rejected.
_Avoid_: timer, countdown

**Intermission**:
The gap between one Round and the next, showing final standings and announcing
the next Theme.
_Avoid_: break, halftime, lobby

**Theme**:
The category a Round draws its Questions from, randomized per Round.
_Avoid_: topic, subject, genre

### Content

**Question**:
A prompt with two to four Choices, exactly one of which is correct, carrying a
Theme and a Difficulty.
_Avoid_: item, trivia, card

**Choice**:
One of the possible answers presented for a Question.
_Avoid_: option, alternative

**Difficulty**:
One of easy, medium, or hard. Ascends across a Round's Slots.
_Avoid_: level, tier

**Bank**:
The full corpus of Questions available to draw from.
_Avoid_: pool, library, deck

### People

**Player**:
An authenticated identity taking part, anonymous or linked. Distinct from a
visitor, who is merely watching.
_Avoid_: user, account, participant

**Bot**:
A Player that plays headlessly through the API rather than the app. Ranked on
its own Leaderboard.
_Avoid_: agent, script, client

**Handle**:
A Player's generated public identifier, shaped `emotion-color-animal-NNN`.
Assigned once and never released, even after the Player is reaped.
_Avoid_: username, nickname, slug

**Link**:
Attaching a durable provider (Google, Apple, X) to an anonymous Player so their
progress survives.
_Avoid_: upgrade, register, sign-up

### Scoring

**Answer**:
A Player's Choice for one Slot, written once, within the Window.
_Avoid_: response, submission, guess

**Entry**:
A Player's participation in one Round: their Answers and the score derived from
them. Unranked if the Player joined after the ranking threshold.
_Avoid_: result, record, play

**Leaderboard**:
A ranking of Players. The live one covers the current Round; the all-time one
ranks by average Entry score above a minimum-Rounds threshold. Bots and humans
rank separately.
_Avoid_: standings, rankings, board

### Operations

**Tick**:
A scheduled action that closes the open Slot, scores it, publishes the
Leaderboard, and opens the next.
_Avoid_: cron, job, pulse

**Reaper**:
The scheduled deletion of anonymous Players inactive beyond the configured
window, along with their associated documents.
_Avoid_: cleanup, GC, pruner

**Kill switch**:
The configured state that puts the game into read-only mode when spending
crosses its soft threshold.
_Avoid_: circuit breaker, maintenance mode
