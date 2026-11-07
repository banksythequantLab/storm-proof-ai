# Storm Proof AI

**No signal. Still answers.**

Storm Proof AI is a free offline kit for emergencies. It puts an offline library, a world map, US and Canada address search and directions, and local AI models on your own computer. Once installed, all of it works with no internet or cell service.

This installer downloads every part from its original public source (Kiwix, Protomaps, GraphHopper, Geofabrik, GitHub, Ollama). Nothing comes from us, so the download only uses your own bandwidth.

## What's in the kit

| Part | What it is | Download |
|---|---|---|
| `library` | Wikipedia (full, with pictures), WikiMed and MDWiki medical encyclopedias, and survival guides for water, food, knots and post-disaster | ~139 GB |
| `maps` | Street-level map of the whole world (Protomaps daily build) | ~139 GB |
| `search` | US and Canada address search (Photon) | ~16 GB download, ~24 GB unpacked |
| `routing` | US and Canada turn-by-turn directions (Valhalla). It builds ~23 GB of road tiles on first start, which takes several hours | ~19 GB |
| `ai` | Everyday models: Qwen 3.6 35B without refusals and Qwen3 4B (fast) | ~26 GB |
| `ai-big` | gpt-oss 120B without refusals (needs a 128 GB machine) | ~87 GB |
| `coding` | Qwen3 Coder 30B and Qwen3 Coder Next | ~69 GB |
| `extras` | iFixit repair guides and the MedGemma 27B medical model. Loaded drives ship without these for licensing reasons; this adds them free | ~21 GB |
| `vibe` | Offline vibe coding: [aider](https://aider.chat) wired to the local coding model. Install it with `coding` | ~0.6 GB |

All parts together come to about 511 GB. Run `--list` for exact sizes.

## Requirements

- Ubuntu Linux (24.04 or newer) and `sudo`.
- **Library and maps only:** any 64-bit PC and a 1 TB drive.
- **Full kit with all AI models:** a 128 GB Ryzen AI Max+ 395 machine. That's the chip the kit is tested on. Examples are the Framework Desktop, the Nimo Axis and the GMKtec EVO-X2.
- **Smaller AI for 32–64 GB machines:** coming. This is not tested yet.

## Install

```bash
git clone https://github.com/banksythequantLab/storm-proof-ai.git
cd storm-proof-ai
bash stormproof-install.sh --list                          # what's available, with sizes
sudo bash stormproof-install.sh --dry-run                  # checks every download link, writes nothing
sudo bash stormproof-install.sh --only library,maps        # install some parts
sudo bash stormproof-install.sh                            # install everything
```

Options:

- `--dir /path` installs somewhere else. The default is `/opt/stormproof`.
- `--no-services` downloads only and doesn't start any servers.
- `--yes` skips the confirmation prompt.

If a download stops, run the same command again and it picks up where it left off. Library files are checked against Kiwix's published SHA-256 checksums. The installer won't start if your drive doesn't have room for what you picked.

## Bought a loaded drive?

Drives from the Storm Proof store come with everything except `extras`. To add the iFixit guides and the MedGemma medical model free, plug in to the internet once and run:

```bash
sudo bash stormproof-install.sh --only extras
```

## Test it before you need it

Unplug the internet, then run:

```bash
sudo bash stormproof-install.sh --check
```

If every line says `ok` with the Wi-Fi off, the kit will work in an outage.

## Vibe code offline

```bash
sudo bash stormproof-install.sh --only coding,vibe
cd ~/my-project && vibe                 # chat in the terminal; it writes and edits the files
vibe --browser                          # the same thing in a web page (not tested yet)
VIBE_MODEL=qwen3-coder-next:latest vibe # use the bigger coder
```

`vibe` talks only to the AI server on your own computer. Tested Nov 7, 2026 with all internet traffic blocked: it wrote a working program from a one-line request. At startup it tries once to fetch a price list, prints a warning when that fails, and carries on.

## Where things run

| Service | Address |
|---|---|
| Library | `http://<this computer>:8090` |
| Map files | `http://<this computer>:8080/maps/world.pmtiles` |
| Address search | `127.0.0.1:2322`, proxied at `:8080/search/` |
| Directions | `127.0.0.1:8002`, proxied at `:8080/route/` |
| AI models | Ollama at `127.0.0.1:11434` |

Phones on the same network can open the library in a browser.

## Status

This is version 0.1.0. Here is what has been tested so far:

- **Tested:** every download link resolves and is reachable, real library downloads pass their checksums, `vibe` installs (including on Ubuntu 26.04 with Python 3.14) and writes working code with the internet blocked, a re-run with nothing new does nothing, the offline check works, and archives unpack.
- **Not tested end to end yet:** a full 510 GB install on a fresh machine, and the map, search and directions services.

The map viewer web app and offline voice are coming in a later release.

## Important

- The AI gives information from medical references for when help can't reach you. It is not a doctor. Call 911 when you can.
- The "without refusals" models will answer how-to questions that other AIs decline. Use them responsibly.

## Licenses

The installer is MIT licensed (see `LICENSE`). The content it downloads keeps its own licenses. See `NOTICE.md`.

---

Made by Banksy AI LLC. Loaded drives, mesh radios and merch are coming at the Storm Proof AI store.
