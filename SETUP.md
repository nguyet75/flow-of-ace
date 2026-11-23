# Turning on accounts (Supabase)

Flow of Ace runs without accounts until `config.js` has a Supabase URL and key. These steps take about 15 minutes. Google sign-in (part 3) is optional; email and password work without it.

Live app: https://nguyet75.github.io/flow-of-ace/

## 1. Create the Supabase project

1. Sign up at https://supabase.com (you can sign in with GitHub) and click **New project**.
2. Name it `flow-of-ace`, set a database password (save it somewhere safe), and pick the region closest to your players (for Europe, Frankfurt).
3. When the project is ready, open **SQL Editor → New query**, paste the whole of [`supabase/schema.sql`](supabase/schema.sql), and click **Run**. It should say "Success. No rows returned".

## 2. Email sign-in and the app's address

1. **Authentication → URL Configuration**
   - **Site URL:** `https://nguyet75.github.io/flow-of-ace/`
   - **Redirect URLs:** add `https://nguyet75.github.io/flow-of-ace/`
2. **Authentication → Sign In / Providers → Email**: leave it on, with **Confirm email** on.
3. **Project Settings → API**: copy the **Project URL** and the **anon / publishable** key. Send both to Claude, or put them in `config.js`. The anon key is designed to be public; the row-level security rules in `schema.sql` are what protect each player's data. Never share the `service_role` / secret key.

## 3. Google sign-in (optional)

1. Go to https://console.cloud.google.com, create a project (`flow-of-ace`).
2. **APIs & Services → OAuth consent screen**: External, app name "Flow of Ace", your support email. Add the scopes `email`, `profile`, `openid`.
3. **APIs & Services → Credentials → Create credentials → OAuth client ID** → Web application.
   - **Authorized JavaScript origins:** `https://nguyet75.github.io`
   - **Authorized redirect URIs:** the callback URL shown in Supabase under **Authentication → Sign In / Providers → Google** (it looks like `https://<project>.supabase.co/auth/v1/callback`).
4. Copy the Client ID and Client secret into Supabase's Google provider and turn it on.
5. While the Google app is in "Testing", only test users you add can sign in. Publish it when you're ready for everyone.

If you skip this, set `googleSignIn: false` in `config.js` so the Google button is hidden.

## Data and privacy

- Each player can only read and change their own profile and sessions (row-level security on every table).
- Players can delete their match data or their whole account from inside the app.
- As the project owner you can see all data in the Supabase dashboard. The in-app privacy note says so.
- The profile asks players to confirm they're 16+ or have a parent's or guardian's agreement. Check the rules for your country before inviting younger players.
