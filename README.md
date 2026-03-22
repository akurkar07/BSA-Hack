# ENS Pay

ENS Pay is a hackathon project for human-readable crypto payments in Telegram.

This repo currently contains two app surfaces:

- a Python Telegram bot in [`main.py`](./main.py)
- a Telegram Mini App in [`index.html`](./index.html)

The Mini App is the main demo surface. It resolves ENS names client-side, connects a TON wallet with TON Connect, and builds a TON payment flow inside Telegram.

## What It Does

- resolve an ENS name such as `vitalik.eth`
- show the resolved EVM address
- generate a TON payment link and QR code
- open a TON wallet from the Telegram Mini App
- store a simple receipt payload in Telegram CloudStorage

## Repo Layout

- [`index.html`](./index.html): single-file Telegram Mini App UI
- [`tonconnect-manifest.json`](./tonconnect-manifest.json): TON Connect manifest, rewritten by the launcher with the live ngrok URL
- [`main.py`](./main.py): Python Telegram bot MVP
- [`start_enspay.ps1`](./start_enspay.ps1): starts the bot, static server, and ngrok together
- [`requirements.txt`](./requirements.txt): Python dependencies for the bot
- [`logs/`](./logs): runtime logs created by the launcher
- [`runtime/`](./runtime): session metadata created by the launcher

## Requirements

- Python 3
- ngrok installed locally
- a Telegram bot token in [`.env`](./.env)

## Environment Setup

Create a local [`.env`](./.env) file with:

```env
BOT_TOKEN=your_telegram_bot_token_here
```

The current Python bot reads `BOT_TOKEN` from `.env` on startup.

## Important App Config

Before demoing the Mini App, update the `CONFIG` object in [`index.html`](./index.html):

- replace `tonRecipient` with your real TON wallet address
- optionally set `botUsername` if you want a Telegram return URL after wallet handoff

The Mini App currently sends native TON. It does not yet send USDT jettons.

## Install Dependencies

```powershell
python -m pip install -r requirements.txt
```

## Run Everything

The easiest way to launch the project is:

```powershell
cd "c:\Users\al3xk\OneDrive\Code\BSA Hack"
powershell -ExecutionPolicy Bypass -File ".\start_enspay.ps1"
```

This script:

- starts the Python bot
- serves [`index.html`](./index.html) on `http://127.0.0.1:8000`
- starts `ngrok http 8000`
- prints the public Mini App URL
- rewrites [`tonconnect-manifest.json`](./tonconnect-manifest.json) with the live ngrok URL

## BotFather Setup

After the launcher prints the public URL:

1. Open `@BotFather`
2. Run `/mybots`
3. Select your bot
4. Open `Bot Settings`
5. Open `Menu Button`
6. Choose `Configure menu button`
7. Set the button text, for example `Open ENS Pay`
8. Paste the printed `https://.../index.html` URL

## Manual Run

If you do not want to use the launcher, start each piece manually.

Mini App server:

```powershell
cd "c:\Users\al3xk\OneDrive\Code\BSA Hack"
python -m http.server 8000
```

ngrok tunnel:

```powershell
ngrok http 8000
```

Python bot:

```powershell
python main.py
```

## Testing the Mini App

1. Launch the stack with [`start_enspay.ps1`](./start_enspay.ps1)
2. Put the printed ngrok URL into BotFather as the Menu Button URL
3. Open your bot in Telegram
4. Tap the menu button
5. Connect a TON wallet
6. Enter an ENS name such as `vitalik.eth`
7. Enter a TON amount
8. Tap `Resolve ENS`
9. Use the Telegram MainButton to send the payment

## Testing the Python Bot

Start the bot:

```powershell
python main.py
```

Then in Telegram:

```text
/start
/pay vitalik.eth 1
```

## Notes

- The Mini App is the primary demo path.
- The Python bot and the Mini App are separate surfaces.
- If you restart ngrok, the public URL changes, so you need to update BotFather again.
- The launcher writes logs to [`logs/`](./logs) and session data to [`runtime/`](./runtime).

## Current Limitations

- native TON payment flow only, not jetton USDT
- no backend verification of chain settlement
- ENS resolution depends on public Ethereum RPC endpoints

