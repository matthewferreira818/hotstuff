# Crew job cards

A job card is one small, honest record of a job handed from one crew chat to another. Matthew watches the cards live in The Helm (Command Core › Crew Station › Jobs), with the real time of each step.

Why a file and not just a message: a woken chat can lose the message text (delegation demo #1). The card lives in a file on this Mac, so the job survives.

## The stages

```
assigned  →  got it (ack)  →  started  →  done (with proof)
                                       ↘  failed (with a reason)
```

- **assigned**: Friday (or whoever hands it off) made the card.
- **got it**: you've seen it. Do this first, right away.
- **started**: you've begun the work.
- **done**: finished, with proof (a commit, a link, or a screenshot path).
- **failed**: you couldn't finish, with the plain reason.

If a job gets no "got it", Friday can resend it.

## The commands

Run these from any crew chat on this Mac. `--by` is your own chat name (for example `LC-Pixels`).

```
python3 tools/crew/job.py ack   <id> --by <you>
python3 tools/crew/job.py start <id> --by <you>
python3 tools/crew/job.py done  <id> --by <you> --proof "<commit sha, link or screenshot path>"
python3 tools/crew/job.py fail  <id> --by <you> --why "<plain reason>"
```

To look things up:

```
python3 tools/crew/job.py show <id>
python3 tools/crew/job.py list            # open jobs
python3 tools/crew/job.py list --all      # every job
```

Handing one off (Friday's side):

```
python3 tools/crew/job.py new <to> "<short title>" --by Friday     # prints the job id, J-...
python3 tools/crew/job.py resend <id> --by Friday                   # when no "got it" came back
```

Job ids look like `J-1106-145401` (month, day, time).

## Where the file lives

`~/Claude/crew-jobs/jobs.jsonl` on this Mac only. One event per line; the folder is private to Matthew's user (700). It is **never in git**: don't commit it, don't copy it into a repo, don't paste it into the room.

The Helm reads this same file for the Jobs card. Nothing else writes it.

## The rule on titles

A title is a work label only: what the job is, in a few plain words, one line, at most 140 characters. Proof lines are at most 300.

Never put in a job card:
- private chat text (anything from "Friday & me", or anything Matthew said to a chat);
- secrets (keys, tokens, passwords, the ntfy topic);
- personal details (addresses, phone numbers, account numbers).

If the work needs any of that, the card says only *where* it is, never *what* it is.

## Good manners

- Ack within a few minutes of being woken, even if you can't start yet.
- One job per chat at a time; finish or fail it before taking another.
- Proof means something another chat can check: a commit sha and branch, a link, a screenshot path.
- A fail is not a problem; a silent stall is. Say why, in one line.
