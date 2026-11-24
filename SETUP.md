# Turning on accounts (Supabase)

Flow of Ace runs without accounts until `config.js` has a Supabase URL and key. These steps take about 15 minutes. Google sign-in (part 3) is optional; email and password work without it.

Live app: https://nguyet75.github.io/flow-of-ace/

## 1. Create the Supabase project

1. Sign up at https://supabase.com (you can sign in with GitHub) and click **New project**.
2. Name it `flow-of-ace`, set a database password (save it somewhere safe), and pick the region closest to your players (for Europe, Frankfurt).
3. When the project is ready, open **SQL Editor → New query**, paste the whole of [`supabase/schema.sql`](supabase/schema.sql), and click **Run**. It should say "Success. No rows returned". The file is safe to run again whenever it changes (for example after an app update adds teams or new fields).

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

## Teams and coaches

- In their profile, each person picks **For myself**, **With my team** or **I'm a coach**.
- Coaches create a team in the coach dashboard and get a 6-letter code. Players enter it under **Account → Teams** and choose what the coach sees: **Summary** (energy, nerves, breathing method, between-set checks, flow and performance ratings, practice counts) or **Everything** (also goals, cues and if-then plans).
- Coaches only see sessions from the day a player joined. Players can switch sharing or leave at any time; coaches can remove players or regenerate the code.
- All team access runs through database functions that check who is asking (tested against Postgres 16 before release).

## Data and privacy

- Each player can only read and change their own profile and sessions (row-level security on every table).
- Players can delete their match data or their whole account from inside the app.
- As the project owner you can see all data in the Supabase dashboard. The in-app privacy note says so.
- The profile asks for birth year and requires explicit consent for wellbeing data (GDPR Art. 9). Players who may be under 15 (the Czech digital consent age) must confirm a parent's or guardian's agreement. The app can't verify that agreement; if you run team programmes with minors, collect written parental consent through the club as well.
- Players can download all their data from the Account screen.

## Roles: player, coach, admin

- Everyone who signs up is a **player**.
- Only an **admin** can make someone a **coach** (Admin screen → tap Player / Coach on a person). Coaches can create teams and see the players who join with the team code.
- Admins are not chosen in the app. Add the admin's email in Supabase → SQL Editor:

  ```sql
  insert into foa_private.admin_emails values (lower('admin@example.com'));
  ```

  The account gets the admin role when it signs up (or on its next profile save if it already exists). Keep admin emails out of this repository.
- The admin sees every account's profile and full session history and every team. The in-app privacy notice and consent text say so.
