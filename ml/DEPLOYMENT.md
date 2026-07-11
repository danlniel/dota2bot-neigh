# OrangePi Deployment Plan

Target: always-on ML server on the Orange Pi 4 Pro (`192.168.18.200`, aarch64,
Ubuntu Jammy, Docker 29 + Compose v5), reachable by friends over the internet
at `https://dota.sunarjodaniel.xyz`.

## Topology

```
friends' Dota clients ──https──> Cloudflare edge (TLS, DDoS shield)
                                     │ Cloudflare Tunnel (outbound-only)
                                     ▼
                        OrangePi: cloudflared ──> 127.0.0.1:5544 dota2bot-ml
your Dota client     ──http──> 192.168.18.200:5544 (LAN direct, lower latency)
```

**Why Cloudflare Tunnel instead of port forwarding:**
- No router changes, no dynamic-DNS problem (tunnel is outbound-only).
- Free TLS at the edge; your home IP stays hidden.
- Ports 80/443 on the Pi stay with Pi-hole — nothing existing is touched.
- The Pi already runs Home Assistant/Pi-hole/MQTT; the ML server (~30 MB RAM,
  near-zero idle CPU) is a rounding error.

## Steps

1. **Container** (done by Claude): copy `ml/` to the Pi, create `ml/.env` with a
   generated `ML_API_KEY` (never committed), `docker compose up -d --build`.
   Container binds `127.0.0.1:5544` on the Pi plus LAN; dataset + model persist
   in the `ml/data` volume.
2. **Verify LAN** (done by Claude): from the Mac, `curl http://192.168.18.200:5544/policy`
   with and without the key (expect 200 / 401).
3. **Tunnel** (needs your Cloudflare login, one time):
   - Cloudflare dashboard → Zero Trust → Networks → Tunnels → Create tunnel
     (name: `dota2bot`), choose Debian arm64, copy the install command with token.
   - Run it on the Pi (or paste the token to Claude to finish).
   - Add public hostname: `dota.sunarjodaniel.xyz` → `http://localhost:5544`.
4. **Client config** for friends (in their `Customize/general.lua`):
   ```lua
   Customize.ML.Server = 'https://dota.sunarjodaniel.xyz'
   Customize.ML.Api_Key = '<the key you give them>'
   ```
   You keep `http://192.168.18.200:5544` locally (skip a WAN round trip).

## Known risk to verify in-game

The addon VM (`MLDirector`) definitely supports HTTPS (`Chat.lua` already calls
an https endpoint). The bots VM client (`ml_bridge.lua`, `CreateRemoteHTTPRequest`)
has only been seen with http URLs in this codebase — HTTPS support is
unverified. First friend to test: check the console for `[MLBridge]` lines.
If HTTPS fails in the bots VM, fallback is a Cloudflare **http** hostname
(disable "Always Use HTTPS" for this subdomain) — the API key still gates
access, and the payloads are non-sensitive game stats.

## Operations

- Logs: `docker logs -f dota2bot-ml`
- Retrain: `docker exec dota2bot-ml python3 train.py && docker restart dota2bot-ml`
- Update: `scp -r ml/ pi:... && docker compose up -d --build`
- The dataset is anonymous game snapshots (no names/chat); one shared model
  learns from everyone's games.
