# Stream buddy — a free AI that watches your stream

While you're live, it looks at your Twitch stream every 20 seconds and
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

## 3. Install the two helper pieces

    python3 -m pip install --user streamlink imageio-ffmpeg

(If your Mac asks to install developer tools, click **Install**, then run
the line again.)

## 4. Get the latest code

If you already set up the stock bot, just update it:

    cd ~/hotstuff && git pull

If not:

    git clone https://github.com/matthewferreira818/hotstuff.git ~/hotstuff

## 5. Go live on Twitch, then start it

    cd ~/hotstuff && python3 tools/stream_buddy/stream_buddy.py

Comments appear in that window. Stop it with **Ctrl + C**.

## If it's slow or struggling

Your MacBook has 8 GB of memory, so the AI shares it with everything else.

- Close other big apps (Chrome tabs especially) while streaming.
- Look less often: `python3 tools/stream_buddy/stream_buddy.py --every 30`
- Try a smaller AI: `ollama pull qwen2.5vl:3b`, then add `--model qwen2.5vl:3b`
- The first comment is always slowest, because the AI is loading.

## What the messages mean

- **"Ollama isn't running"**: open the Ollama app.
- **"Model isn't downloaded"**: run step 2.
- **"Not live right now"**: it checks every 30 seconds and starts by itself
  when you go live.
