-- CodeArena canonical database. PostgreSQL 16.
-- Machine-normative stored shape. Update this file in the same pull request
-- as any doc or API change that touches persistence.
-- Apply through Prisma migrations that produce this end state. Do not let
-- application servers run migrations on boot when more than one replica exists.

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email citext NOT NULL UNIQUE,
  username text NOT NULL UNIQUE,
  password_hash text NOT NULL,
  display_name text NOT NULL CHECK (char_length(display_name) BETWEEN 1 AND 40),
  role text NOT NULL DEFAULT 'player' CHECK (role IN ('player', 'setter', 'admin')),
  rating integer NOT NULL DEFAULT 1200 CHECK (rating >= 100 AND rating <= 4000),
  rated_matches integer NOT NULL DEFAULT 0 CHECK (rated_matches >= 0),
  wins integer NOT NULL DEFAULT 0 CHECK (wins >= 0),
  losses integer NOT NULL DEFAULT 0 CHECK (losses >= 0),
  draws integer NOT NULL DEFAULT 0 CHECK (draws >= 0),
  email_verified_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT username_format CHECK (username ~ '^[a-z0-9_]{3,20}$')
);

CREATE INDEX users_rating_idx ON users (rating DESC, wins DESC, username);

CREATE TABLE refresh_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  token_hash text NOT NULL UNIQUE,
  family_id uuid NOT NULL,
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  replaced_by uuid REFERENCES refresh_tokens (id),
  user_agent text,
  ip inet,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX refresh_tokens_user_idx ON refresh_tokens (user_id);

CREATE TABLE password_reset_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  token_hash text NOT NULL UNIQUE,
  expires_at timestamptz NOT NULL,
  used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE email_verification_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  token_hash text NOT NULL UNIQUE,
  expires_at timestamptz NOT NULL,
  used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE problems (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  language text NOT NULL CHECK (language IN ('c', 'cpp', 'python', 'javascript')),
  difficulty text NOT NULL CHECK (difficulty IN ('easy', 'medium', 'hard')),
  round_type text NOT NULL CHECK (round_type IN ('syntax', 'predict', 'logic', 'fix')),
  title text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 120),
  prompt_md text NOT NULL,
  starter_code text,
  explanation_md text NOT NULL,
  options jsonb,
  correct_option_id text,
  time_limit_ms integer NOT NULL DEFAULT 2000,
  memory_limit_kb integer NOT NULL DEFAULT 131072,
  is_published boolean NOT NULL DEFAULT false,
  reference_passed_at timestamptz,
  created_by uuid REFERENCES users (id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT code_rounds_have_starter CHECK (
    round_type NOT IN ('syntax', 'fix') OR (
      starter_code IS NOT NULL AND char_length(starter_code) > 0
    )
  ),
  CONSTRAINT choice_rounds_have_options CHECK (
    round_type NOT IN ('predict', 'logic') OR (
      options IS NOT NULL AND correct_option_id IS NOT NULL AND starter_code IS NOT NULL
    )
  ),
  CONSTRAINT choice_rounds_have_no_use_for_runtime CHECK (
    round_type NOT IN ('predict', 'logic') OR time_limit_ms = 2000
  ),
  CONSTRAINT time_limit_cap CHECK (time_limit_ms BETWEEN 100 AND 5000),
  CONSTRAINT memory_limit_cap CHECK (memory_limit_kb BETWEEN 32768 AND 262144)
);

CREATE INDEX problems_pick_idx
  ON problems (language, difficulty, round_type)
  WHERE is_published;

CREATE TABLE test_cases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  problem_id uuid NOT NULL REFERENCES problems (id) ON DELETE CASCADE,
  visibility text NOT NULL CHECK (visibility IN ('sample', 'hidden')),
  ordinal integer NOT NULL CHECK (ordinal >= 1),
  input_text text NOT NULL,
  expected_output text NOT NULL,
  UNIQUE (problem_id, visibility, ordinal)
);

CREATE INDEX test_cases_problem_idx ON test_cases (problem_id, visibility, ordinal);

CREATE TABLE matches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  origin text NOT NULL CHECK (origin IN ('quick', 'lobby')),
  rated boolean NOT NULL,
  language text NOT NULL CHECK (language IN ('c', 'cpp', 'python', 'javascript')),
  difficulty text NOT NULL CHECK (difficulty IN ('easy', 'medium', 'hard')),
  status text NOT NULL CHECK (status IN ('countdown', 'live', 'final', 'void')),
  countdown_ends_at timestamptz,
  current_round integer CHECK (current_round BETWEEN 1 AND 4),
  winner_user_id uuid REFERENCES users (id),
  end_reason text CHECK (
    end_reason IS NULL OR end_reason IN (
      'completed', 'draw', 'forfeit', 'void_early', 'void_no_problem'
    )
  ),
  created_at timestamptz NOT NULL DEFAULT now(),
  started_at timestamptz,
  ended_at timestamptz,
  CONSTRAINT final_has_end CHECK (
    status NOT IN ('final', 'void') OR ended_at IS NOT NULL
  )
);

CREATE INDEX matches_status_idx ON matches (status, created_at);
CREATE INDEX matches_created_idx ON matches (created_at DESC);

CREATE TABLE match_players (
  match_id uuid NOT NULL REFERENCES matches (id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users (id),
  seat integer NOT NULL CHECK (seat IN (1, 2)),
  rating_before integer NOT NULL,
  rating_after integer,
  total_score integer NOT NULL DEFAULT 0 CHECK (total_score BETWEEN 0 AND 400),
  total_correct_time_ms integer NOT NULL DEFAULT 0 CHECK (total_correct_time_ms >= 0),
  outcome text CHECK (outcome IS NULL OR outcome IN ('win', 'loss', 'draw')),
  last_disconnected_at timestamptz,
  forfeit boolean NOT NULL DEFAULT false,
  PRIMARY KEY (match_id, user_id),
  UNIQUE (match_id, seat)
);

CREATE INDEX match_players_user_idx ON match_players (user_id, match_id);

CREATE TABLE match_rounds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id uuid NOT NULL REFERENCES matches (id) ON DELETE CASCADE,
  round_index integer NOT NULL CHECK (round_index BETWEEN 1 AND 4),
  round_type text NOT NULL CHECK (round_type IN ('syntax', 'predict', 'logic', 'fix')),
  problem_id uuid NOT NULL REFERENCES problems (id),
  snapshot jsonb NOT NULL,
  duration_ms integer NOT NULL CHECK (duration_ms > 0),
  starts_at timestamptz,
  ends_at timestamptz,
  intermission_ends_at timestamptz,
  status text NOT NULL CHECK (status IN ('pending', 'active', 'intermission', 'closed')),
  UNIQUE (match_id, round_index)
);

CREATE TABLE round_scores (
  match_id uuid NOT NULL REFERENCES matches (id) ON DELETE CASCADE,
  round_index integer NOT NULL CHECK (round_index BETWEEN 1 AND 4),
  user_id uuid NOT NULL REFERENCES users (id),
  correct boolean NOT NULL,
  score integer NOT NULL CHECK (score BETWEEN 0 AND 100),
  time_used_ms integer CHECK (time_used_ms IS NULL OR time_used_ms >= 0),
  wrong_attempts integer NOT NULL DEFAULT 0 CHECK (wrong_attempts >= 0),
  selected_option_id text,
  PRIMARY KEY (match_id, round_index, user_id)
);

CREATE TABLE submissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id uuid NOT NULL REFERENCES matches (id) ON DELETE CASCADE,
  round_index integer NOT NULL CHECK (round_index BETWEEN 1 AND 4),
  user_id uuid NOT NULL REFERENCES users (id),
  kind text NOT NULL CHECK (kind IN ('graded', 'sample')),
  language text NOT NULL CHECK (language IN ('c', 'cpp', 'python', 'javascript')),
  source_text text,
  option_id text,
  status text NOT NULL CHECK (status IN ('queued', 'running', 'judged', 'expired', 'error')),
  verdict text CHECK (
    verdict IS NULL OR verdict IN (
      'accepted',
      'wrong_answer',
      'compile_error',
      'runtime_error',
      'time_limit',
      'memory_limit',
      'output_limit',
      'internal_error',
      'rejected'
    )
  ),
  tests_passed integer CHECK (tests_passed IS NULL OR tests_passed >= 0),
  tests_total integer CHECK (tests_total IS NULL OR tests_total >= 0),
  received_at timestamptz NOT NULL DEFAULT now(),
  judged_at timestamptz,
  counted boolean NOT NULL DEFAULT false,
  idempotency_key text NOT NULL,
  CONSTRAINT submission_payload CHECK (
    (source_text IS NOT NULL AND option_id IS NULL)
    OR (source_text IS NULL AND option_id IS NOT NULL)
  ),
  UNIQUE (user_id, idempotency_key)
);

CREATE INDEX submissions_round_idx
  ON submissions (match_id, round_index, user_id, received_at);

CREATE INDEX submissions_queued_idx
  ON submissions (status, received_at)
  WHERE status IN ('queued', 'running');

CREATE TABLE submission_tests (
  submission_id uuid NOT NULL REFERENCES submissions (id) ON DELETE CASCADE,
  ordinal integer NOT NULL,
  visibility text NOT NULL CHECK (visibility IN ('sample', 'hidden')),
  verdict text NOT NULL,
  time_ms integer,
  stdout_excerpt text,
  PRIMARY KEY (submission_id, ordinal)
);

CREATE TABLE rating_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users (id),
  match_id uuid NOT NULL REFERENCES matches (id) ON DELETE CASCADE,
  rating_before integer NOT NULL,
  rating_after integer NOT NULL,
  delta integer NOT NULL,
  k integer NOT NULL,
  expected_score numeric(8, 6) NOT NULL,
  actual_score numeric(3, 2) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, match_id)
);

CREATE INDEX rating_events_user_idx ON rating_events (user_id, created_at DESC);

CREATE TABLE lobbies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE CHECK (char_length(code) = 6),
  host_user_id uuid NOT NULL REFERENCES users (id),
  language text NOT NULL CHECK (language IN ('c', 'cpp', 'python', 'javascript')),
  difficulty text NOT NULL CHECK (difficulty IN ('easy', 'medium', 'hard')),
  status text NOT NULL CHECK (status IN ('open', 'countdown', 'started', 'cancelled', 'expired')),
  match_id uuid REFERENCES matches (id),
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX lobbies_status_idx ON lobbies (status, expires_at);

CREATE TABLE lobby_players (
  lobby_id uuid NOT NULL REFERENCES lobbies (id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users (id),
  joined_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (lobby_id, user_id)
);

CREATE TABLE seen_problems (
  user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  problem_id uuid NOT NULL REFERENCES problems (id),
  match_id uuid NOT NULL REFERENCES matches (id) ON DELETE CASCADE,
  seen_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, problem_id, match_id)
);

CREATE INDEX seen_problems_recent_idx ON seen_problems (user_id, seen_at DESC);

CREATE TABLE pair_history (
  user_low uuid NOT NULL REFERENCES users (id),
  user_high uuid NOT NULL REFERENCES users (id),
  match_id uuid NOT NULL REFERENCES matches (id) ON DELETE CASCADE,
  rated boolean NOT NULL,
  played_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (match_id),
  CONSTRAINT pair_order CHECK (user_low < user_high)
);

CREATE INDEX pair_history_lookup_idx ON pair_history (user_low, user_high, played_at DESC);

CREATE TABLE idempotency_keys (
  user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  key text NOT NULL,
  request_hash text NOT NULL,
  response_code integer NOT NULL,
  response_body jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, key)
);

CREATE TABLE audit_log (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  actor_user_id uuid REFERENCES users (id),
  action text NOT NULL,
  entity_type text NOT NULL,
  entity_id uuid,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX audit_log_entity_idx ON audit_log (entity_type, entity_id, created_at DESC);

-- Live-match exclusion is enforced with pg_advisory_xact_lock on each user id
-- inside the match-create and queue-join transactions. A partial unique index
-- cannot express "this user is in a match whose status is countdown or live"
-- without a redundant column kept in sync. Do not skip the advisory lock.
