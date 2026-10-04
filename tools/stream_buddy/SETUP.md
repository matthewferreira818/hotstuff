# Stream buddy — a free AI that watches your stream

While you're live, it looks at your Twitch stream every 30 seconds and
prints one short line about what's happening ("low health — pop a potion",
"inventory open, Battle Banner equipped"). It runs on your Mac.

- **Free.** The AI runs on your own Mac, so there are no per-picture costs.
- **Text only.** Comments print in a Terminal window. Nothing is posted
  anywhere, and no picture leaves your Mac.
- **Honest limit:** it's a small free model, not Claude. Good at "what's on
  screen", weaker at deep build advice, and a few seconds behind the stream.

One-time setup, about 20 minutes (mostly the download).

## 1. Install Ollama (the free AI runner)

Download it from https://ollama.com (Mac), open it, and leave it running. It
sits in the menu bar at the top of the screen.

## 2. Download the AI that can see (about 3.3 GB)

Open **Terminal** and paste:

    ollama pull gemma3:4b

## 3. Give it its own Python, with the two helper pieces

Paste these one at a time. The first makes a private Python just for the
stream buddy, so it can't clash with anything else on the Mac:

    python3 -m venv ~/.streambuddy
    ~/.streambuddy/bin/pip install streamlink imageio-ffmpeg

(A yellow "newer version of pip" warning is harmless. If your Mac asks to
install developer tools, click **Install**, then run the line again.)

## 4. Get the latest code

If you already set up the stock bot, just update it:

    cd ~/hotstuff && git pull

If not:

    git clone https://github.com/matthewferreira818/hotstuff.git ~/hotstuff

## 5. Go live on Twitch, then start it

    cd ~/hotstuff && ~/.streambuddy/bin/python tools/stream_buddy/stream_buddy.py

That line is your start command from now on. Comments appear in that
window; the first one takes 30-60 seconds while the AI loads. Stop it with
**Ctrl + C**.

## If it's slow or lagging the Mac

Your MacBook has 8 GB of memory, and the AI shares it with everything else.
Between looks the Mac is idle (it takes one picture every 30 seconds, then
stops), but each look still works it hard for a few seconds.

- Close other big apps (Chrome tabs especially) while it runs.
- Look less often:

      cd ~/hotstuff && ~/.streambuddy/bin/python tools/stream_buddy/stream_buddy.py --every 60

- Use the lightest AI (about half the memory, less sharp):

      ollama pull moondream
      cd ~/hotstuff && ~/.streambuddy/bin/python tools/stream_buddy/stream_buddy.py --model moondream

- The first comment is always slowest, because the AI is loading.

## What the messages mean

- **"Ollama isn't running"**: open the Ollama app.
- **"Model isn't downloaded"**: run step 2.
- **"No streamlink"**: you started it with plain `python3`; use the start
  command above (it uses the private Python from step 3).
- **"Couldn't open the stream"**: it prints Twitch's reason, checks again
  every 30 seconds, and starts by itself once you're live.
