from rest_framework import serializers
from .models import Crop

class CropSerializer(serializers.ModelSerializer):
    # Always return a single, display-ready URL for the image
    imageUrl = serializers.SerializerMethodField()

    class Meta:
        model = Crop
        fields = [
            "id",
            "name",
            "spacing",
            "harvest_time",
            "growth_stages",
            "pest_notes",
            "image",        # raw ImageField path (optional, kept for admin/debug)
            "image_path",   # optional manual URL override
            "imageUrl",     # computed public URL for the app
        ]
        read_only_fields = ["id", "imageUrl"]

    def get_imageUrl(self, obj):
        request = self.context.get("request")
        if getattr(obj, "image", None) and hasattr(obj.image, "url") and obj.image:
            url = obj.image.url
            return request.build_absolute_uri(url) if request else url
        if getattr(obj, "image_path", ""):
            return obj.image_path
        return ""
