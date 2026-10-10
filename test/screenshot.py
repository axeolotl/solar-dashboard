#!/usr/bin/env python3
"""Screenshot a Grafana dashboard (needs: pip install playwright &&
python3 -m playwright install chromium).

usage: screenshot.py <dashboard-url> <out.png> <user> <password>
"""
import asyncio, sys
from urllib.parse import urlsplit
from playwright.async_api import async_playwright

url, out, user, password = sys.argv[1:5]
base = "{0.scheme}://{0.netloc}".format(urlsplit(url))

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.launch()
        page = await browser.new_page(viewport={"width": 1600, "height": 1000}, ignore_https_errors=True)
        await page.goto(base + "/login")
        await page.fill("input[name=user]", user)
        await page.fill("input[name=password]", password)
        await page.keyboard.press("Enter")
        await page.wait_for_timeout(3000)
        await page.goto(url)
        await page.wait_for_timeout(8000)  # let all panels render
        await page.screenshot(path=out, full_page=True)
        await browser.close()

asyncio.run(main())
