CREATE TABLE IF NOT EXISTS notes (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id text NOT NULL,
    title text NOT NULL,
    preview text NOT NULL,
    content text NOT NULL,
    tags text[] DEFAULT '{}'::text[],
    is_pinned boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);

CREATE INDEX IF NOT EXISTS notes_user_id_idx ON notes(user_id);
