// Flow of Ace runtime config.
// Fill in from Supabase: Project Settings → API (Project URL and the "anon" / publishable key).
// The anon key is meant to be public: every table is protected by row-level security (see supabase/schema.sql).
// Leave both empty to run the app without accounts (everything stays on the device).
window.FOA_CONFIG = {
  supabaseUrl: 'https://muysknbjlecjfwcjlcax.supabase.co',
  supabaseAnonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im11eXNrbmJqbGVjamZ3Y2psY2F4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTU1NDA1NDQsImV4cCI6MjExMTExNjU0NH0.PH84bKl9RBJVmTOdGE-IrKw3WTkeBJuK7Ln0jtMPv6M',
  googleSignIn: false,
  // Club default playlists (Spotify links). Players can override them with their own.
  playlists: { calm: '', hype: '' }
};
