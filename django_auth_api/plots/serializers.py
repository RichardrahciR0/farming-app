from rest_framework import serializers
from .models import Plot, CropMedia


class CropMediaSerializer(serializers.ModelSerializer):
    url = serializers.SerializerMethodField(read_only=True)

    class Meta:
        model = CropMedia
        fields = ["id", "url", "caption", "created_at"]
        read_only_fields = ["id", "url", "created_at"]

    def get_url(self, obj):
        request = self.context.get("request")
        if obj.image and hasattr(obj.image, "url"):
            return request.build_absolute_uri(obj.image.url) if request else obj.image.url
        return None


class PlotSerializer(serializers.ModelSerializer):
    images = CropMediaSerializer(many=True, read_only=True)

    class Meta:
        model = Plot
        fields = [
            "id", "type", "geometry", "name", "notes",
            "growth_stage", "planted_at",
            "created_at", "updated_at",
            "images",
        ]
        read_only_fields = ["id", "created_at", "updated_at", "images"]

    def validate(self, attrs):
        # Minimal geometry validation (you can harden later)
        g = attrs.get("geometry")
        t = attrs.get("type") or (self.instance.type if self.instance else None)
        if not g or not t:
            return attrs

        if t == "point":
            if not isinstance(g, dict) or g.get("type") != "Point" or not isinstance(g.get("coordinates"), list):
                raise serializers.ValidationError("Point geometry must be GeoJSON-like with coordinates [lng, lat].")

        if t in ("rectangle", "polygon"):
            if not isinstance(g, dict) or g.get("type") != "Polygon" or not isinstance(g.get("coordinates"), list):
                raise serializers.ValidationError("Rectangle/Polygon geometry must be GeoJSON-like Polygon.")
            # Optionally check 4 corners for rectangle, closed ring, etc.

        if t == "circle":
            if not isinstance(g, dict) or "center" not in g or "radiusMeters" not in g:
                raise serializers.ValidationError("Circle geometry must contain center [lng,lat] and radiusMeters.")

        return attrs
