// Flow of Ace runtime config.
// Fill in from Supabase: Project Settings → API (Project URL and the "anon" / publishable key).
// The anon key is meant to be public: every table is protected by row-level security (see supabase/schema.sql).
// Leave both empty to run the app without accounts (everything stays on the device).
window.FOA_CONFIG = {
  supabaseUrl: '',
  supabaseAnonKey: '',
  googleSignIn: true
};
