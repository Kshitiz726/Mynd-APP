-- ============ ROOM JOIN CODES ============
--
-- Every room gets a short, human-sayable code. It is the only way into a
-- private room, and a convenient way into a public one: "join 4K9P" is a thing
-- you can text a friend or say out loud, where a UUID is not.
--
-- The alphabet deliberately excludes 0/O and 1/I/L. A code exists to be read
-- off one screen and typed into another, and those pairs are where that goes
-- wrong.

alter table rooms add column if not exists code text;

-- Backfill existing rooms with a code before we add the unique index.
do $$
declare
  r record;
  candidate text;
  alphabet  text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
begin
  for r in select id from rooms where code is null loop
    loop
      candidate := '';
      for _i in 1..4 loop
        candidate := candidate || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
      end loop;
      exit when not exists (select 1 from rooms where code = candidate);
    end loop;
    update rooms set code = candidate where id = r.id;
  end loop;
end $$;

-- Codes are only meaningful while a room is live, but uniqueness has to hold
-- across the whole table or a code could resolve to two rooms mid-handoff.
create unique index if not exists rooms_code_uniq on rooms (code);
