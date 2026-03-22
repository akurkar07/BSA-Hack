# ENS payment request bot MVP
import os
from decimal import Decimal, InvalidOperation
from uuid import uuid4

import aiohttp
from aiogram import Bot, Dispatcher, types, executor
from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup
from dotenv import load_dotenv

load_dotenv()

BOT_TOKEN = os.getenv("BOT_TOKEN")
if not BOT_TOKEN:
    raise ValueError("BOT_TOKEN is not set. Add it to your environment or .env file.")

bot = Bot(token=BOT_TOKEN)
dp = Dispatcher(bot)

DEFAULT_ENS_RESOLVERS = [
    "https://api.ensideas.com/ens/resolve/{ens_name}",
    "https://ethereum-gateway.ens.domains/api/v1/resolve/{ens_name}",
]
ETHERSCAN_ADDRESS_URL = "https://etherscan.io/address/{address}"
ENS_APP_NAME_URL = "https://app.ens.domains/{ens_name}"


def get_resolver_urls() -> list[str]:
    override = os.getenv("ENS_RESOLVER_URL")
    if override:
        return [override]

    return DEFAULT_ENS_RESOLVERS


async def resolve_ens(ens_name: str) -> tuple[str | None, str | None]:
    timeout = aiohttp.ClientTimeout(total=5)
    network_errors: list[str] = []

    async with aiohttp.ClientSession(timeout=timeout) as session:
        for template in get_resolver_urls():
            url = template.format(ens_name=ens_name)

            try:
                async with session.get(url) as response:
                    if response.status == 404:
                        continue

                    if response.status != 200:
                        network_errors.append(f"{url} returned HTTP {response.status}")
                        continue

                    payload = await response.json()
            except (aiohttp.ClientError, TimeoutError, ValueError) as exc:
                network_errors.append(f"{url} failed: {exc}")
                continue

            address = payload.get("address")
            if not isinstance(address, str):
                continue

            if not address.startswith("0x") or len(address) != 42:
                continue

            return address, None

    if network_errors:
        return None, "network"

    return None, "not_found"


def parse_amount(raw_amount: str) -> Decimal | None:
    try:
        amount = Decimal(raw_amount)
    except InvalidOperation:
        return None

    if amount <= 0:
        return None

    return amount.quantize(Decimal("0.01"))


def build_payment_request_message(ens_name: str, amount: Decimal, address: str) -> str:
    request_id = uuid4().hex[:8].upper()
    amount_text = format(amount.normalize(), "f")

    return "\n".join(
        [
            "ENS payment request",
            f"Request ID: {request_id}",
            f"Payee: {ens_name}",
            f"Resolved address: `{address}`",
            f"Requested amount: {amount_text} USDT",
            "",
            "MVP note: this bot resolves ENS and prepares the payment request.",
            "Settlement still happens in the payer's wallet.",
        ]
    )


def build_payment_request_keyboard(ens_name: str, address: str) -> InlineKeyboardMarkup:
    keyboard = InlineKeyboardMarkup(row_width=1)
    keyboard.add(
        InlineKeyboardButton(
            text="View Address on Etherscan",
            url=ETHERSCAN_ADDRESS_URL.format(address=address),
        )
    )
    keyboard.add(
        InlineKeyboardButton(
            text="View ENS Profile",
            url=ENS_APP_NAME_URL.format(ens_name=ens_name),
        )
    )
    return keyboard


@dp.message_handler(commands=["start", "help"])
async def show_help(message: types.Message) -> None:
    await message.reply(
        "\n".join(
            [
                "Send `/pay alice.eth 50` to create an ENS payment request.",
                "The bot resolves the ENS name and returns the recipient address.",
                "Use this MVP to make wallet-ready payment requests for your demo.",
            ]
        ),
        parse_mode="Markdown",
    )


@dp.message_handler(commands=["pay"])
async def create_payment_request(message: types.Message) -> None:
    args = message.text.split(maxsplit=2)
    if len(args) < 3:
        await message.reply(
            "Usage: `/pay alice.eth 50`\nExample: `/pay vitalik.eth 1`",
            parse_mode="Markdown",
        )
        return

    ens_name = args[1].strip().lower()
    amount = parse_amount(args[2].strip())

    if not ens_name.endswith(".eth"):
        await message.reply("Please provide a valid `.eth` name.")
        return

    if amount is None:
        await message.reply("Please provide a valid positive amount, for example `1` or `12.50`.")
        return

    await message.reply(f"Resolving `{ens_name}`...", parse_mode="Markdown")
    address, error_type = await resolve_ens(ens_name)
    if not address:
        if error_type == "network":
            await message.reply(
                "The ENS lookup service is unreachable right now. "
                "Please try again in a moment or switch networks.",
            )
        else:
            await message.reply(
                f"`{ens_name}` did not resolve to a wallet address.",
                parse_mode="Markdown",
            )
        return

    await message.reply(
        build_payment_request_message(ens_name, amount, address),
        parse_mode="Markdown",
        reply_markup=build_payment_request_keyboard(ens_name, address),
        disable_web_page_preview=True,
    )


if __name__ == "__main__":
    print("ENS payment request bot starting...")
    executor.start_polling(dp, skip_updates=True)
