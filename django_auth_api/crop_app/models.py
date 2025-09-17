from django.db import models

class Crop(models.Model):
    name = models.CharField(max_length=255)
    image = models.ImageField(upload_to="crops/", blank=True, null=True)  # stored under MEDIA_ROOT/crops/
    image_path = models.URLField(max_length=1000, blank=True, null=True)  # optional absolute URL override
    spacing = models.FloatField(blank=True, null=True)
    harvest_time = models.CharField(max_length=100, blank=True)
    growth_stages = models.JSONField(blank=True, null=True)               # e.g. ["Seedling","Vegetative","Flowering","Harvest"]
    pest_notes = models.TextField(blank=True, null=True)

    def __str__(self):
        return self.name
