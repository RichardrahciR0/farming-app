# crop_backend/crops/serializers.py
from rest_framework import serializers
import re
from .models import Crop

class GrowthStagesField(serializers.Field):
    """
    Accepts ["A","B"] or "A|B" on input.
    - If model uses CharField -> we join as "A|B" to save.
    - If model uses JSONField/List -> we pass a list to save.
    """

    def to_representation(self, value):
        # DB -> API
        if isinstance(value, list):
            return value
        if isinstance(value, str):
            return [s.strip() for s in re.split(r"[,\|]", value) if s.strip()]
        return []

    def to_internal_value(self, data):
        # API -> DB
        if isinstance(data, list):
            # Try to detect model type from instance field (CharField vs JSONField)
            try:
                from django.db import models
                field = Crop._meta.get_field("growth_stages")
                if isinstance(field, models.CharField):
                    return "|".join(str(s) for s in data)
            except Exception:
                pass
            return list(map(str, data))  # JSON/List field path
        if isinstance(data, str):
            return data
        raise serializers.ValidationError("Must be a list or string.")

class CropSerializer(serializers.ModelSerializer):
    # Map other names if you want:
    imagePath = serializers.CharField(source="image", required=False, allow_blank=True)
    harvestTime = serializers.CharField(source="harvest_time", required=False, allow_blank=True)
    pestNotes = serializers.CharField(source="pest_notes", required=False, allow_blank=True)

    growth_stages = GrowthStagesField(required=False)

    class Meta:
        model = Crop
        fields = ["id", "name", "spacing", "growth_stages", "harvest_time", "image", "pest_notes",
                  "imagePath", "harvestTime", "pestNotes"]
