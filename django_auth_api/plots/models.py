from django.conf import settings
from django.db import models


class Plot(models.Model):
    class PlotType(models.TextChoices):
        POINT = "point", "Point"
        RECTANGLE = "rectangle", "Rectangle"
        CIRCLE = "circle", "Circle"
        POLYGON = "polygon", "Polygon"

    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="plots"
    )
    type = models.CharField(max_length=16, choices=PlotType.choices)
    # Geometry stored as JSON (GeoJSON-like for point/rectangle/polygon; {center:[lng,lat], radiusMeters:n} for circle)
    geometry = models.JSONField()

    name = models.CharField(max_length=120)
    notes = models.TextField(blank=True, default="")

    growth_stage = models.CharField(max_length=64, blank=True, default="")
    planted_at = models.DateField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.name} ({self.type})"


def plot_media_path(instance, filename):
    # media/plot_images/<user_id>/<plot_id>/<filename>
    return f"plot_images/{instance.plot.owner_id}/{instance.plot_id}/{filename}"


class CropMedia(models.Model):
    plot = models.ForeignKey(Plot, on_delete=models.CASCADE, related_name="images")
    image = models.ImageField(upload_to=plot_media_path)
    caption = models.CharField(max_length=200, blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"Media for plot {self.plot_id}"
