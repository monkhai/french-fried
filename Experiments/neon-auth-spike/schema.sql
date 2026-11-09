-- Use an isolated development branch only.
CREATE TABLE spike_notes (
  user_id text PRIMARY KEY,
  note text NOT NULL CHECK (char_length(note) <= 200)
);
