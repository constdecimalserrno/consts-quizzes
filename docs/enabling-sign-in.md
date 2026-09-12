# Enabling sign-in providers

Linking is built and deployed; the providers themselves are off, because
turning one on needs credentials from a console only you can reach. Until
they are on, the save prompt appears, the button works, and it reports that
the provider is not switched on yet.

Everything below is done once. None of it changes any code.

## Google — about two minutes

1. Open the [sign-in providers page](https://console.firebase.google.com/project/consts-quizzes/authentication/providers).
2. Add provider, Google, enable.
3. Pick a support email.
4. Save.

Firebase creates the OAuth client for you. Nothing else is needed — this is
the only provider that works without a developer account.

## X — needs an X developer account

1. At [developer.x.com](https://developer.x.com), create an app.
2. Set its callback URL to `https://consts-quizzes.firebaseapp.com/__/auth/handler`.
   It must be the `firebaseapp.com` domain and not a custom one: X's OAuth 1.0a
   return always lands on the default handler, and a custom `authDomain`
   produces "missing initial state" or `invalid-credential` instead.
3. Request "Read" permission and enable "Sign in with X".
4. Copy the API key and secret into the Firebase console's X provider.

Ticket #11 — importing an X name, avatar and banner — cannot be finished
until this is done, because the profile fields it reads only arrive on a real
link.

## Apple — needs a paid Apple Developer account

1. In the Apple developer portal create a **Services ID** (not an App ID).
2. Enable "Sign in with Apple" on it and add
   `https://consts-quizzes.firebaseapp.com/__/auth/handler` as the return URL.
3. Create a **Sign in with Apple key**, download the `.p8` once — Apple will
   not show it again.
4. Put the Services ID, Team ID, Key ID and the key's contents into the
   Firebase console's Apple provider.

Apple is the slowest of the three and the only one with a yearly fee, so it is
reasonable to leave it until the iOS build actually exists.

## Checking it worked

Open the site, play until a Round ends with a score, and take the save
prompt. A provider that is on will either link silently — keeping your
Handle — or, if that account already exists, sign you in as it and combine
the two histories.
