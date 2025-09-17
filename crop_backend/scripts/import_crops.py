#!/usr/bin/env python3
import argparse, json, requests, sys

def login(base, email, password):
    url = f"{base}/api/auth/jwt/create/"
    r = requests.post(url, json={"email": email, "password": password}, timeout=30)
    r.raise_for_status()
    return r.json()["access"]

def main():
    ap = argparse.ArgumentParser(description="Bulk import crops via API.")
    ap.add_argument("--base", default="http://127.0.0.1:8000", help="Base URL, e.g. http://127.0.0.1:8000")
    ap.add_argument("--email", required=True)
    ap.add_argument("--password", required=True)
    ap.add_argument("--file", required=True, help="Path to JSON array of crops")
    args = ap.parse_args()

    with open(args.file, "r", encoding="utf-8") as f:
        data = json.load(f)
        if not isinstance(data, list):
            print("JSON must be an array of objects.", file=sys.stderr)
            sys.exit(1)

    token = login(args.base, args.email, args.password)
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

    ok, fail = 0, 0
    for item in data:
        # your DRF expects snake_case: name, spacing, harvest_time, growth_stages, pest_notes, (optional) image
        r = requests.post(f"{args.base}/api/crops/", headers=headers, json=item, timeout=30)
        if r.status_code in (200, 201):
            body = r.json()
            print(f"✅ {body.get('id')} {body.get('name')}")
            ok += 1
        else:
            fail += 1
            print(f"❌ {r.status_code}: {r.text}")

    print(f"\nDone. Success={ok}, Fail={fail}")

if __name__ == "__main__":
    main()
