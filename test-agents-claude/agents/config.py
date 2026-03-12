"""
config.py - Centralized configuration for CDM-Manager agents.
Loads from .env if present, falls back to hardcoded defaults.
"""

import os
from dotenv import load_dotenv

load_dotenv()

# Power BI workspace / dataset IDs
DEV_WORKSPACE_ID  = os.getenv("PBI_DEV_WORKSPACE_ID",  "2696b15d-427e-437b-ba5a-ca8d4fb188dd")
PROD_WORKSPACE_ID = os.getenv("PBI_PROD_WORKSPACE_ID", "c05c8a73-79ee-4b7f-b798-831b5c260f1b")
PROD_DATASET_ID   = os.getenv("PBI_PROD_DATASET_ID",   "10ad1784-d53f-4877-b9f0-f77641efbff4")

# Repository root directory
REPO_DIR = os.getenv(
    "REPO_DIR",
    r"H:\GitRepos\Airgas\Power BI Workflow\ProductionCDM-main"
)

# Well-known report / template name
LIVE_TEMPLATE_NAME = "Live Connection Template"

# Path to the Power BI bearer token written by CDM-Manager
PBI_TOKEN_PATH = os.path.join(
    os.environ.get("TEMP", os.environ.get("TMP", "/tmp")),
    "pbi_token.txt"
)
