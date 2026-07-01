# DIY Mailer

Self-hosted outbound SMTP with DKIM signing — Postfix + OpenDKIM in Docker.

Designed for transactional email from apps that speak generic SMTP (Nodemailer, `smtplib`, etc.).

## Quick install

```bash
curl -fsSL https://raw.githubusercontent.com/darioguarascio/diy-mailer/master/install.sh | bash
```

This clones the repo and runs an **interactive setup wizard** (domain, network, DKIM keys, DNS records). Press Enter at each prompt to accept defaults.

**If `curl | bash` or `wget | bash` only clones the repo and stops** (no prompts appear), the pipe stole stdin from the wizard. Continue manually:

```bash
cd ~/diy-mailer && bash scripts/setup.sh
```

Or download first (most reliable):

```bash
curl -fsSL https://raw.githubusercontent.com/darioguarascio/diy-mailer/master/install.sh -o install.sh
bash install.sh
```

Or with `wget`:

```bash
wget -qO install.sh https://raw.githubusercontent.com/darioguarascio/diy-mailer/master/install.sh
bash install.sh
```

If you used `wget -qO- ... | bash` and the wizard did not start, run `bash scripts/setup.sh` as above.

Custom install directory:

```bash
INSTALL_DIR=/opt/diy-mailer curl -fsSL .../install.sh | bash
```

The installer clones this repo, walks you through domain and network setup (including DNS records and DKIM key generation), builds containers, and prints what to publish.

## What you get

| Component    | Role                                              |
| ------------ | ------------------------------------------------- |
| **Postfix**  | Outbound SMTP relay (port 25)                     |
| **OpenDKIM** | Signs every message with per-domain DKIM keys     |
| **Scripts**  | Setup wizard, DNS checklist, test send, add domain |

This stack is **send-only**. Inbound mail (bounces, replies) is handled separately — see [Bounce monitoring](#bounce-monitoring).

## Architecture

```
┌─────────────┐   SMTP :25    ┌──────────────┐   milter    ┌───────────┐
│  Your app   │ ────────────► │   Postfix    │ ──────────► │ OpenDKIM  │
│  (Docker)   │  no auth*     │   (mailer)   │   sign      │           │
└─────────────┘               └──────┬───────┘             └───────────┘
                                     │
                                     ▼
                              recipient MX servers
                              (Gmail, Outlook, …)

* trusted networks only (mynetworks)
```

Typical production layout:

- Postfix bound to a **host internal IP** (e.g. `<internal-ip>:25`) — reachable from app containers on the same machine, not from the internet
- Apps set `SMTP_HOST` to that same internal IP
- Public **A record** for your SMTP hostname → server IP (for PTR + SPF only — port 25 stays internal)
- **MX** on each sending domain via your email provider (inbound, not this stack)

## Setup wizard

```bash
bash scripts/setup.sh
```

Use this for **initial installation**. If a domain is already configured, the script asks whether to add another domain or reconfigure from scratch.

The wizard will:

1. Ask how many sending domains you need
2. Ask for one **shared SMTP hostname** (A + PTR + HELO) — e.g. `mail.example.com` on a domain you control
3. For each sending domain: name and DKIM selector (same hostname for all)
4. Generate a DKIM key pair per domain
5. Print DNS records (A, SPF, DKIM, DMARC) for each domain, merging existing SPF where found
6. Write `.env` and `domains.conf`

**To add another domain** after the initial setup (keeps existing domains and keys):

```bash
bash scripts/add-domain.sh
```

Running `setup.sh` again with an existing config defaults to `add-domain.sh`. Choose "reconfigure from scratch" only if you want to replace all domains and network settings.

## Manual setup

```bash
git clone https://github.com/darioguarascio/diy-mailer.git
cd diy-mailer
cp .env.example .env
cp domains.conf.example domains.conf   # edit with your domains (not committed)
docker compose up -d --build
bash scripts/show-dkim.sh
bash scripts/check-dns.sh --generate
```

### Multiple domains (`domains.conf`)

Use one SMTP hostname for every domain — one IP, one PTR, one HELO. The hostname can live on a **different** domain from your `From:` addresses:

```
# domain|hostname|selector
example.com|mail.example.com|mail
other.com|mail.example.com|mail
```

The **first** domain is the primary — Postfix uses it for default envelope identity. `MAIL_HOSTNAME` in `.env` must match the shared hostname. OpenDKIM signs each `From:` domain with its own key under `.data/dkim/{domain}/`.

### One IP, many domains — shared host + PTR

You can only set **one PTR record** per sending IP. That is normal for a shared outbound relay:

| What                         | Per domain? | Notes |
| ---------------------------- | ----------- | ----- |
| `From:` address              | Yes         | `noreply@example.com`, `noreply@other.com`, … |
| DKIM key                     | Yes         | `mail._domainkey.{each-domain}` |
| SPF / DMARC                  | Yes         | On each domain's DNS (SPF merged with existing) |
| SMTP hostname (A + PTR)      | **No**      | One name, e.g. `mail.example.com` |
| Postfix HELO                 | **No**      | Must match PTR |

**Checklist for a shared host:**

1. Create `A mail.example.com → YOUR_SERVER_IP` (once)
2. Ask your hoster to set **PTR** for that IP → `mail.example.com`
3. Put `mail.example.com` in the hostname column for every line in `domains.conf`
4. Set `MAIL_HOSTNAME=mail.example.com` in `.env`
5. Per sending domain: publish DKIM + update SPF (add `a:mail.example.com ip4:YOUR_IP` to existing SPF if present)

## Configuration (.env)

| Variable              | Example                    | Description                              |
| --------------------- | -------------------------- | ---------------------------------------- |
| `MAIL_DOMAIN`         | `example.com`              | Primary domain (must match first line in `domains.conf`) |
| `MAIL_HOSTNAME`       | `mail.example.com`         | Shared SMTP hostname (A record + PTR)    |
| `DKIM_SELECTOR`       | `mail`                     | Default DKIM selector                    |
| `SMTP_BIND`           | `127.0.0.1:25:25`          | Docker host port mapping                 |
| `SMTP_RELAY_MYNETWORKS` | `127.0.0.0/8 10.0.0.0/8` | CIDRs allowed to relay without auth      |
| `EMAIL_FROM`          | `noreply@example.com`      | Default sender for test script           |

### App integration

Postfix is **not** exposed on the public internet. Apps on the same host reach it via the **internal IP** you set in `SMTP_BIND` (or via Docker service name on a shared network).

Add to your application `.env`:

```env
SMTP_HOST=<internal-ip>      # same host IP as in SMTP_BIND (internal only)
SMTP_PORT=25
SMTP_SECURE=0
SMTP_USER=
SMTP_PASS=
EMAIL_FROM=noreply@example.com
EMAIL_FROM_NAME=My App
```

When the app runs in Docker on the same host, pick one:

1. **Internal IP (typical)** — bind Postfix to a host private IP (`SMTP_BIND=<internal-ip>:25:25`), set `SMTP_HOST=<internal-ip>` in each app. Works from any container on the host that can route to that IP.
2. **Shared Docker network** — connect the mailer container to your app network, set `SMTP_HOST=mailer` (the compose service name).

`scripts/setup.sh` writes `SMTP_HOST` into `.env` from your `SMTP_BIND` choice — copy those `SMTP_*` lines into each app.

No SMTP authentication is configured by default — access is restricted by `mynetworks` (includes `10.0.0.0/8` and Docker CIDRs by default). Do not bind to `0.0.0.0:25` on a public interface without TLS + SASL.

Your app (or mail library) must set **`Date`** and **`Message-ID`** headers on every message — missing headers cost ~1.5 points on mail-tester and hurt inbox placement. Also publish **SPF on the shared SMTP hostname** (not just each sending domain) to pass HELO checks: `v=spf1 a ip4:YOUR_IP -all` on `mail.example.com`.

## DNS records

After first start, get DKIM public keys:

```bash
bash scripts/show-dkim.sh              # all domains
bash scripts/show-dkim.sh example.com  # one domain
```

Publish these records per domain (Cloudflare, Route53, etc.):

| Type | Name                         | Value                                                                 |
| ---- | ---------------------------- | --------------------------------------------------------------------- |
| A    | `smtp.mail.example.com`      | Your server public IPv4                                               |
| TXT  | `example.com`                | `v=spf1 a:smtp.mail.example.com ip4:YOUR_SERVER_IP -all`              |
| TXT  | `mail._domainkey.example.com`| Paste output from `show-dkim.sh`                                      |
| TXT  | `_dmarc.example.com`         | `v=DMARC1; p=none; rua=mailto:dmarc@example.com; pct=100`             |

Generate a table for all configured domains:

```bash
bash scripts/check-dns.sh --generate
```

### SPF

Start with `p=none` in DMARC while testing. Tighten to `p=quarantine` then `p=reject` once confident.

If you use a provider for inbound email routing, include their SPF mechanism alongside your sending server IP.

### PTR / rDNS

Your hosting provider must set **reverse DNS** for the server IP to match `MAIL_HOSTNAME`. Without matching PTR, Gmail and others may reject or spam-folder your mail.

Verify:

```bash
bash scripts/check-dns.sh
bash scripts/check-dns.sh --domain example.com
```

### Deliverability test

1. Get a test address at [mail-tester.com](https://www.mail-tester.com)
2. `bash scripts/send-test.sh test-xxxxx@mail-tester.com`
3. Aim for **9+/10** before sending production traffic

## Bounce monitoring

This Postfix container sends mail only (`mydestination = localhost`). **Bounces** (delivery failures) are returned to the envelope sender (`MAIL FROM`, usually `noreply@example.com`). To receive and monitor them:

### Option A — Email provider routing (recommended)

1. Enable inbound email routing on your domain (Cloudflare Email Routing, etc.)
2. MX records point to your provider
3. Create a rule: `noreply@example.com` → forward to `bounces@your-inbox.com`
4. Or route `dmarc@example.com` for DMARC aggregate reports

### Option B — Catch-all forward

Use your DNS provider's email forwarding to pipe bounces to a monitored inbox or webhook.

### Option C — Receive bounces on this server

Only if you control MX and want Postfix to receive:

1. Point MX for `example.com` to your SMTP hostname
2. Expand `mydestination` in `postfix/main.cf`
3. Add alias: `noreply: |/usr/local/bin/bounce-handler.sh`
4. Monitor `.data/mailer/bounces.log`

Postfix already logs bounces in `.data/mailer/mail.log` (`notify_classes = bounce, defer`).

### Suppression list

The mailer does not maintain a suppression list. Your application should:

- Stop sending to addresses that hard-bounce
- Honor unsubscribe / notification preferences
- Parse bounce notifications from your inbound mailbox or webhook

## Open & click tracking

Open/click tracking is **application-level**, not part of this SMTP stack. Your web app serves tracking endpoints and stores events.

| Endpoint              | Purpose                          |
| --------------------- | -------------------------------- |
| `GET /e/o/{id}.gif`   | 1×1 transparent pixel (open)     |
| `GET /e/c/{id}/{idx}` | Click redirect (302 to real URL) |

Requirements:

1. `SITE_URL` in app env points to your public web app
2. DNS for your app domain (separate from `smtp.mail.*`)
3. Routes are public (no auth) — tracking pixels must load in email clients
4. Store events in your database

The mailer only delivers the HTML your app generates; it does not inject tracking pixels.

## Local development

For local dev without DNS, use console logging in your app (omit `SMTP_HOST`) or bind to localhost:

```bash
SMTP_BIND=127.0.0.1:25:25 docker compose up -d
```

Alternative: [Mailpit](https://mailpit.axllent.org/) for a web UI inbox (no real delivery).

## Operations

```bash
docker compose logs -f mailer     # Postfix logs
docker compose logs -f opendkim     # DKIM signing
docker compose restart            # after config changes
```

Logs persist in `.data/mailer/mail.log`.

## Security notes

- Do **not** expose unauthenticated SMTP on `0.0.0.0:25` to the internet
- Bind to `127.0.0.1` or a private IP (`SMTP_BIND`)
- Restrict `SMTP_RELAY_MYNETWORKS` to trusted CIDRs
- DKIM private keys live in `.data/dkim/` — back up and restrict permissions
- Rotate DKIM keys periodically; publish new TXT before removing old

## Publishing as open source

```bash
cd diy-mailer
git init
git add .
git commit -m "Initial release: DIY Mailer — Postfix + OpenDKIM"
gh repo create your-org/diy-mailer --public --source=. --push
```

Update the repo URL in `install.sh` if you fork.

## License

MIT — see [LICENSE](LICENSE).
