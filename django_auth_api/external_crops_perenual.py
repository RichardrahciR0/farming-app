# django_auth_api/external_crops_perenual.py
import os
import logging
from typing import Dict, Any, List, Optional

import requests
from django.http import JsonResponse
from django.views.decorators.http import require_GET
from django.views.decorators.csrf import csrf_exempt

logger = logging.getLogger(__name__)

# === Config ===
PERENUAL_KEY = os.environ.get("PERENUAL_KEY", "").strip()
BASE_URL = "https://perenual.com/api"
SPECIES_LIST = f"{BASE_URL}/species-list"
SPECIES_DETAILS = f"{BASE_URL}/species/details"  # + /{id}

# A static final fallback so the app always shows *something*
PLACEHOLDER_IMG = "https://via.placeholder.com/300x200?text=No+Image"


def _pick_image_from_item(item: Dict[str, Any]) -> str:
    """Best-effort extraction of an image URL from a list/detail item."""
    img = item.get("default_image") or {}
    # Prefer a larger "regular_url" if present, else "thumbnail"
    return img.get("regular_url") or img.get("thumbnail") or ""


def _normalize_item(item: Dict[str, Any]) -> Dict[str, Any]:
    """
    Map Perenual fields to your Crop schema.
    Note: Perenual doesn't provide spacing/harvest_time/growth_stages/pest_notes in list.
    """
    name = item.get("common_name")
    if not name:
        # fall back to first scientific_name if available
        sci = item.get("scientific_name")
        if isinstance(sci, list) and sci:
            name = sci[0]
        elif isinstance(sci, str):
            name = sci
        else:
            name = "Unknown"

    image_url = _pick_image_from_item(item)

    return {
        "id": item.get("id"),
        "name": name,
        "image_path": image_url,  # may be empty; we'll fill later
        "spacing": None,
        "harvest_time": None,
        "growth_stages": [],
        "pest_notes": None,
    }


def _fetch_details_image(plant_id: Any, timeout: float = 8.0) -> Optional[str]:
    """Call /species/details/{id} to try to get a better image."""
    if not plant_id:
        return None
    try:
        r = requests.get(
            f"{SPECIES_DETAILS}/{plant_id}",
            params={"key": PERENUAL_KEY},
            timeout=timeout,
        )
        r.raise_for_status()
        data = r.json()
        url = _pick_image_from_item(data)
        return url or None
    except Exception as e:
        logger.debug("details fetch failed for %s: %s", plant_id, e)
        return None


@csrf_exempt
@require_GET
def external_crops_search(request):
    """
    GET /api/external/crops/?q=apple&page=1&limit=24&details=1

    Responds in your normalized format:
    {
      "page": 1,
      "count": 24,
      "results": [
        { "id":..., "name":"...", "image_path":"...", ... }
      ]
    }
    """
    if not PERENUAL_KEY:
        return JsonResponse({"error": "PERENUAL_KEY missing (set env var)"}, status=500)

    q = (request.GET.get("q") or "").strip()
    page = int(request.GET.get("page", "1") or 1)
    limit = max(1, min(int(request.GET.get("limit", "24") or 24), 50))  # cap to 50
    use_details = request.GET.get("details", "0") in ("1", "true", "True")

    params = {"key": PERENUAL_KEY, "page": page}
    if q:
        params["q"] = q

    try:
        resp = requests.get(SPECIES_LIST, params=params, timeout=12.0)
        upstream_status = resp.status_code
        resp.raise_for_status()
        payload = resp.json()
    except Exception as e:
        return JsonResponse({"error": f"Upstream error: {e}"}, status=502)

    data_list: List[Dict[str, Any]] = payload.get("data") or []

    # Normalize and trim to 'limit' (perenual page size can be 30)
    normalized: List[Dict[str, Any]] = []
    for item in data_list:
        normalized.append(_normalize_item(item))
        if len(normalized) >= limit:
            break

    # If requested, try to fill missing images from details endpoint (only those empty)
    if use_details:
        for row in normalized:
            if not row.get("image_path"):
                details_img = _fetch_details_image(row.get("id"))
                if details_img:
                    row["image_path"] = details_img

    # Final fallback so your Flutter UI always has an image URL string to attempt
    for row in normalized:
        if not row.get("image_path"):
            row["image_path"] = PLACEHOLDER_IMG

    # Optional: quick log for backend console
    logger.info(
        "[perenual] q=%r page=%s limit=%s details=%s -> %d items (upstream %s)",
        q, page, limit, use_details, len(normalized), upstream_status
    )

    return JsonResponse(
        {
            "page": page,
            "count": len(normalized),
            "results": normalized,
        }
    )
