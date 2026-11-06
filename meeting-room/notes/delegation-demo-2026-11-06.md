# Delegation demo #1 (Fri Nov 6, 2026): Friday hands a real job to LC-Pixels

Matthew's ask (via Roxy's plan): one small Command Core improvement, delegated by Friday without Matthew managing the handoff,
LC-Pixels visibly working in The Helm (real status + timer), evidence at the end, Friday verifies, nothing merged without his OK.
Every step below is logged as it happens, failures included. Times are Moncton.

| Time | Step | What actually happened |
|---|---|---|
| 14:24 | 1. Job chosen | Friday picked a known small polish item: Crew Station's legend wraps onto two lines at the 1000×680 minimum (LC-Pixels flagged it earlier). Goal: one line, no clipping, at 1000×680 and maximized. |
| 14:24 | 2. Handoff, try 1 | FAILED: LC-Pixels chat was closed (the app restart at ~1:55 closed most chats); direct message refused "not reachable". The Helm was not running either, so the Switchboard could not wake it. |
| 14:24 | 2. Handoff, try 2 | Job posted in the room addressed to LC-Pixels (the Switchboard wakes a closed chat for a room message once The Helm is open). Waiting for The Helm to be opened. |
| 14:29 | 3. Wake | The Switchboard DID wake LC-Pixels once The Helm was open (its chat was open by 14:28), but my job text never reached it: it asked me to resend. |
| 14:29 | Ended | Matthew cancelled the handoff ("you can do it"); Friday does the job herself. Lessons: (1) delegation needs the crew chats open or The Helm running; (2) a wake opens the chat but does not carry the job text, so the job must be re-sent after the wake; (3) a job card in The Helm showing assigned/started/done would have made both problems visible at once. |

# Delegation demo #2 (same day, with job cards): PASSED end to end

| Time (Moncton) | Step | What actually happened |
|---|---|---|
| 14:54:01 | Assigned | Friday ran `job.py new LC-Pixels "Write tools/crew/README.md…"` → J-1106-145401, then messaged LC-Pixels the id and the exact commands. |
| 14:56:33 | Got it | LC-Pixels ran `job.py ack` (about 2.5 min: its chat picked up the message on its next step). |
| 14:56:55 | Started | `job.py start`. |
| 14:57:22 | Done | `job.py done --proof "3e602cd on pixels/job-readme"`. |
| 14:58 | Verified | Friday checked the proof herself: commit 3e602cd exists, is based on friday/job-card, and adds tools/crew/README.md (72 lines, accurate to job.py). Merged into friday/job-card. Not on master. |

What made the difference vs demo #1: the job lived in a file, the chat was open, and each step was recorded by the crew member itself. Matthew could watch the stages appear on Command Core › Crew Station › Jobs in the test copy.
