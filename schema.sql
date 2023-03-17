CREATE TABLE users (
  id serial PRIMARY KEY,
  admin boolean NOT NULL DEFAULT false,
  username varchar(100) NOT NULL UNIQUE,
  password varchar(100) NOT NULL,
  created_at timestamp NOT NULL DEFAULT now()
);

CREATE TABLE discussions (
  id serial PRIMARY KEY,
  title varchar(100) NOT NULL,
  description text NOT NULL,
  date_created date NOT NULL DEFAULT now(),
  time_created time NOT NULL DEFAULT now(),
  user_id integer NOT NULL REFERENCES users (id) ON DELETE CASCADE
);

CREATE TABLE comments (
  id serial PRIMARY KEY,
  discussion_id integer NOT NULL REFERENCES discussions(id) ON DELETE CASCADE,
  user_id integer NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  comment text NOT NULL,
  date_created date NOT NULL DEFAULT now(),
  time_created time NOT NULL DEFAULT now()
);
