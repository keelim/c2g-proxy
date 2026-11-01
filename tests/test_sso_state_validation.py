import unittest
from unittest.mock import AsyncMock

from fastapi_sso.sso.base import SSOLoginError
from fastapi_sso.sso.google import GoogleSSO
from starlette.requests import Request


class SsoStateValidationTests(unittest.IsolatedAsyncioTestCase):
    async def check_callback(self, query, cookie=None):
        provider = GoogleSSO("test-client", "test-secret")
        provider.requires_state = True
        provider.process_login = AsyncMock(return_value={"id": "test-user"})
        headers = [] if cookie is None else [(b"cookie", f"sso_state={cookie}".encode())]
        request = Request({
            "type": "http", "method": "GET", "scheme": "https",
            "server": ("example.invalid", 443), "path": "/callback",
            "query_string": query.encode(), "headers": headers,
        })
        async with provider:
            result = await provider.verify_and_process(request, convert_response=False)
        provider.process_login.assert_awaited_once()
        return result

    async def test_rejects_state_from_another_session(self):
        with self.assertRaisesRegex(SSOLoginError, "Invalid state"):
            await self.check_callback("code=test-code&state=attacker", "trusted-session")

    async def test_rejects_missing_state_cookie(self):
        with self.assertRaisesRegex(SSOLoginError, "State cookie not found"):
            await self.check_callback("code=test-code&state=attacker")

    async def test_rejects_missing_state_parameter(self):
        with self.assertRaisesRegex(SSOLoginError, "state.*not found"):
            await self.check_callback("code=test-code", "trusted-session")

    async def test_matching_session_state_reaches_login(self):
        result = await self.check_callback("code=test-code&state=trusted-session", "trusted-session")
        self.assertEqual(result, {"id": "test-user"})


if __name__ == "__main__":
    unittest.main()
