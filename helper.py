import os
from dotenv import load_dotenv

def check_env_vars():
    """Loads .env and checks for required environment variables."""
    load_dotenv()
    hf_token = os.getenv("HF_TOKEN")
    project_id = os.getenv("PROJECT_ID")
    region = os.getenv("REGION")

    missing_vars = []
    if not hf_token:
        missing_vars.append("HF_TOKEN")
    if not project_id:
        missing_vars.append("PROJECT_ID")
    if not region:
        missing_vars.append("REGION")

    if missing_vars:
        print(f"Error: Missing environment variables in .env file: {', '.join(missing_vars)}")
        print("Please ensure HF_TOKEN, PROJECT_ID, and REGION are set.")
        return False
    else:
        print("✅ Required environment variables (HF_TOKEN, PROJECT_ID, REGION) found.")
        return True
