# Cheating is permitted, and Bots rank separately

Rather than fight clients that inspect their own traffic, we document the API
in `llms.txt` and treat headless play as a feature: a Bot hits the same
endpoints as the app. This makes the game a continuously running trivia
benchmark, which is arguably a sharper product than the game itself.

It also breaks the human Leaderboard. Time-decayed scoring awards a full score
for an instant Answer, so a Bot scores a perfect Round every time and would own
the board permanently. Bots therefore rank on their own Leaderboard, keyed off
the presence of an API key.

## Consequences

The human/Bot split is a category label, not a security boundary — an honour
system, which is consistent with permitting cheating in the first place.
