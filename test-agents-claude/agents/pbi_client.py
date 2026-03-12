"""
pbi_client.py - Thin wrapper around the Power BI REST API.

The bearer token is written to %TEMP%\pbi_token.txt by CDM-Manager after the
OAuth device-code flow completes.  We read it fresh on every instantiation so
that a newly-refreshed token is always picked up.
"""

import os
import requests
from .config import PBI_TOKEN_PATH

_BASE_URL = "https://api.powerbi.com/v1.0/myorg"


class PBIClient:
    def __init__(self):
        if not os.path.isfile(PBI_TOKEN_PATH):
            raise RuntimeError(
                f"Power BI token file not found at {PBI_TOKEN_PATH}. "
                "Open CDM-Manager and sign in first."
            )
        with open(PBI_TOKEN_PATH, "r", encoding="utf-8") as fh:
            token = fh.read().strip()
        if len(token) < 20:
            raise RuntimeError(
                "Power BI token file exists but appears empty or invalid. "
                "Re-authenticate via CDM-Manager."
            )
        self._headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        }

    # ------------------------------------------------------------------
    # Low-level helpers
    # ------------------------------------------------------------------

    def get(self, path: str) -> dict:
        """GET https://api.powerbi.com/v1.0/myorg{path} → parsed JSON."""
        url = f"{_BASE_URL}{path}"
        resp = requests.get(url, headers=self._headers, timeout=30)
        resp.raise_for_status()
        return resp.json()

    def delete(self, path: str) -> int:
        """DELETE https://api.powerbi.com/v1.0/myorg{path} → HTTP status code."""
        url = f"{_BASE_URL}{path}"
        resp = requests.delete(url, headers=self._headers, timeout=30)
        return resp.status_code

    # ------------------------------------------------------------------
    # Workspace / report / dataset helpers
    # ------------------------------------------------------------------

    def get_reports(self, ws_id: str) -> list:
        """Return the list of reports in a workspace."""
        data = self.get(f"/groups/{ws_id}/reports")
        return data.get("value", [])

    def get_datasets(self, ws_id: str) -> list:
        """Return the list of datasets in a workspace."""
        data = self.get(f"/groups/{ws_id}/datasets")
        return data.get("value", [])

    def get_report_pages(self, ws_id: str, report_id: str) -> list:
        """Return the list of pages for a report; returns [] on any error."""
        try:
            data = self.get(f"/groups/{ws_id}/reports/{report_id}/pages")
            return data.get("value", [])
        except Exception:
            return []

    def get_workspace(self, ws_id: str) -> dict:
        """Return the workspace metadata object."""
        return self.get(f"/groups/{ws_id}")

    def delete_report(self, ws_id: str, report_id: str) -> int:
        """Delete a report; returns HTTP status code."""
        return self.delete(f"/groups/{ws_id}/reports/{report_id}")

    def delete_dataset(self, ws_id: str, dataset_id: str) -> int:
        """Delete a dataset; returns HTTP status code."""
        return self.delete(f"/groups/{ws_id}/datasets/{dataset_id}")

    def validate_token(self) -> bool:
        """Probe GET / to verify the token is still live."""
        try:
            self.get("/")
            return True
        except Exception:
            return False
