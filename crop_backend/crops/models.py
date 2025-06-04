from django.db import models

class Crop(models.Model):
    name = models.CharField(max_length=100)
    spacing = models.CharField(max_length=100)
    harvest_time = models.CharField(max_length=100)
    growth_stages = models.TextField(blank=True)  # e.g., seedling, flowering, etc.
    plant_type = models.CharField(max_length=100, blank=True)  # tree, vine, herb, etc.
    soil_type = models.CharField(max_length=100, blank=True)
    watering_needs = models.CharField(max_length=100, blank=True)
    sunlight_needs = models.CharField(max_length=100, blank=True)
    planting_season = models.CharField(max_length=100, blank=True)
    fertiliser_tips = models.TextField(blank=True)
    pest_notes = models.TextField(blank=True)
    image = models.ImageField(upload_to='crop_images/', blank=True, null=True)

    def __str__(self):
        return self.name
