# OrangePi Deployment (as built)

Always-on ML server on the Orange Pi 4 Pro (`192.168.18.200`, aarch64, Ubuntu
Jammy, Docker), publicly reachable at `https://dota.sunarjodaniel.xyz`.
Deployed and verified 2026-07-11.

## Topology

```
friends' Dota clients ──https──> Cloudflare edge (TLS, DDoS shield)
                                     │ existing cloudflared tunnel (outbound-only)
                                     ▼
                        OrangePi: cloudflared ──> localhost:5544 dota2bot-ml
your Dota client     ──http──> 192.168.18.200:5544 (LAN direct, lower latency)
```

The Pi already ran a cloudflared tunnel (systemd service,
`/etc/cloudflared/config.yml`) exposing its other services — the ML server
just follows the same pattern: one ingress rule, one CNAME. No new tunnel,
no port forwarding, Pi-hole keeps ports 80/443.

## What was done

1. **Container**: `ml/` copied to `/home/orangepi/dota2bot-ml/`,
   `ML_API_KEY` generated into `.env` there (never committed),
   `docker compose up -d --build`. Dataset + model persist in `data/`,
   `restart: unless-stopped` survives reboots.
2. **Tunnel ingress**: added to `/etc/cloudflared/config.yml` before the
   catch-all, then validated + restarted cloudflared:
   ```yaml
   - hostname: dota.sunarjodaniel.xyz
     service: http://localhost:5544          # dota2bot ml server
   ```
3. **DNS**: the `dota` CNAME to the tunnel UUID target already existed —
   managed in Cloudflare (nameservers are delegated there; the Porkbun DNS
   panel is inert).
4. **Verified**: `/policy` and `/director` return correct responses with the
   key and 401 without, over LAN and through the tunnel; `GET /health` is up.

## Client config

Friends (in their `Customize/general.lua`):
```lua
Customize.ML.Server = 'https://dota.sunarjodaniel.xyz'
Customize.ML.Api_Key = '<the key you give them>'
```
Locally keep `http://192.168.18.200:5544` (skips the WAN round trip).

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
